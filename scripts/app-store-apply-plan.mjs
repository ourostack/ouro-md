#!/usr/bin/env node
import { createHash, createPrivateKey, sign } from "node:crypto";
import fs from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

function parseArgs(argv) {
  const options = { json: false, transport: "fixture" };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--mode") options.mode = argv[++index];
    else if (arg === "--plan") options.planPath = argv[++index];
    else if (arg === "--transport") options.transport = argv[++index];
    else if (arg === "--transport-fixture") options.transportFixturePath = argv[++index];
    else if (arg === "--config") options.configPath = argv[++index];
    else if (arg === "--stage") options.stage = argv[++index];
    else if (arg === "--preflight") options.preflightPath = argv[++index];
    else if (arg === "--state") options.statePath = argv[++index];
    else if (arg === "--artifact-dir") options.artifactDir = argv[++index];
    else if (arg === "--json") options.json = true;
    else throw new Error(`unknown argument: ${arg}`);
  }
  if (options.transportFixturePath) options.transport = "fixture";
  return options;
}

function validateOptions(options) {
  if (options.mode !== "apply") throw new Error("mutation executor requires --mode apply");
  if (!options.planPath) throw new Error("mutation executor requires --plan <path>");
  if (!["fixture", "live"].includes(options.transport)) throw new Error("mutation executor --transport must be fixture or live");
  if (options.transport === "fixture" && !options.transportFixturePath) {
    throw new Error("mutation executor requires --transport-fixture <path>");
  }
  if (options.transport === "live") {
    const missing = [];
    if (!options.stage) missing.push("live mutation requires --stage <version-graph|metadata|screenshots|build-review|final-submit>");
    if (!options.preflightPath) missing.push("live mutation requires --preflight <path>");
    if (!options.statePath) missing.push("live mutation requires --state <path>");
    if (missing.length > 0) throw new Error(missing.join("; "));
  }
  if (!options.artifactDir) throw new Error("mutation executor requires --artifact-dir <path>");
}

async function applyPlan(options) {
  validateOptions(options);
  const plan = JSON.parse(fs.readFileSync(options.planPath, "utf8"));
  if (options.transport === "live") return applyLivePlan(options, plan);
  return applyFixturePlan(options, plan);
}

function applyFixturePlan(options, plan) {
  const transport = JSON.parse(fs.readFileSync(options.transportFixturePath, "utf8"));
  validatePlan(plan);
  fs.mkdirSync(options.artifactDir, { recursive: true });

  const context = { ids: {}, screenshots: plan.screenshots ?? [] };
  const events = [];
  let uploadOperationCount = 0;

  for (const request of plan.requests ?? []) {
    const resolvedRequest = resolveValue(request, context);
    assertNoUnresolvedPlaceholders(request.id, resolvedRequest);
    const fixtureError = transport.errors?.[request.id];
    if (fixtureError) {
      const failure = redact({
        ok: false,
        retryable: isRetryableStatus(fixtureError.status),
        failedRequestId: request.id,
        status: fixtureError.status,
        message: fixtureError.message
      });
      process.stdout.write(`${JSON.stringify(failure, null, 2)}\n`);
      process.exitCode = 1;
      return;
    }

    if (request.method === "UPLOAD_OPERATIONS") {
      const uploadEvents = executeUploadOperations(request, resolvedRequest, transport, context);
      uploadOperationCount += uploadEvents.length;
      events.push(...uploadEvents);
      events.push(redact({
        kind: "upload-step",
        requestId: request.id,
        dependsOn: request.dependsOn,
        uploadOperationsSource: request.uploadOperationsSource
      }));
      continue;
    }

    events.push(redact({
      kind: "request",
      requestId: request.id,
      method: resolvedRequest.method,
      path: resolvedRequest.path,
      query: resolvedRequest.query,
      body: resolvedRequest.body
    }));

    const response = transport.responses?.[request.id];
    if (response) captureIds(request, response, context);
  }

  const trace = redact({ schemaVersion: 1, mode: "apply", transport: "fixture", events });
  const traceArtifact = join(options.artifactDir, "apply-trace.json");
  fs.writeFileSync(traceArtifact, `${JSON.stringify(trace, null, 2)}\n`);

  return redact({
    schemaVersion: 1,
    ok: true,
    mode: "apply",
    transport: "fixture",
    appId: plan.appId,
    targetVersion: plan.targetVersion,
    executedRequestCount: (plan.requests ?? []).length,
    executedUploadOperationCount: uploadOperationCount,
    resolvedIds: publicResolvedIds(context),
    traceArtifact
  });
}

async function applyLivePlan(options, plan) {
  validatePlan(plan);
  const preflight = JSON.parse(fs.readFileSync(options.preflightPath, "utf8"));
  validateLivePreflight(plan, preflight, options.stage);
  fs.mkdirSync(options.artifactDir, { recursive: true });

  const state = readState(options.statePath);
  validateResolvedState(plan, preflight, state, options.stage);
  const context = {
    ids: { ...(state.resolvedIds ?? {}) },
    screenshots: plan.screenshots ?? [],
    responses: {}
  };
  const client = createAscClient(loadAscConfig(options.configPath));
  const events = [];
  let uploadOperationCount = 0;
  let executedRequestCount = 0;
  const allowedRequests = new Set(stageRequestIds(options.stage, plan));

  for (const request of plan.requests ?? []) {
    if (!allowedRequests.has(request.id)) continue;
    if (shouldSkipCreateRequest(request, context)) {
      events.push(redact({
        kind: "skip",
        requestId: request.id,
        reason: "resolved-id-already-present"
      }));
      continue;
    }

    const resolvedRequest = resolveValue(request, context);
    assertNoUnresolvedPlaceholders(request.id, resolvedRequest);

    if (request.method === "UPLOAD_OPERATIONS") {
      const uploadEvents = await executeLiveUploadOperations(request, resolvedRequest, context);
      uploadOperationCount += uploadEvents.length;
      events.push(...uploadEvents);
      events.push(redact({
        kind: "upload-step",
        requestId: request.id,
        dependsOn: request.dependsOn,
        uploadOperationsSource: request.uploadOperationsSource
      }));
      continue;
    }

    const response = await client.request({
      method: resolvedRequest.method,
      path: resolvedRequest.path,
      query: resolvedRequest.query,
      body: resolvedRequest.body
    });
    executedRequestCount += 1;
    context.responses[request.id] = response;
    captureIds(request, response, context);
    events.push(redact({
      kind: "request",
      requestId: request.id,
      method: resolvedRequest.method,
      path: resolvedRequest.path,
      query: resolvedRequest.query,
      body: resolvedRequest.body,
      response: responseSummary(response)
    }));
  }

  const trace = redact({ schemaVersion: 1, mode: "apply", transport: "live", stage: options.stage, events });
  const traceArtifact = join(options.artifactDir, `apply-${options.stage}-trace.json`);
  fs.writeFileSync(traceArtifact, `${JSON.stringify(trace, null, 2)}\n`);

  const resolvedIds = publicResolvedIds(context);
  writeState(options.statePath, {
    schemaVersion: 1,
    appId: plan.appId,
    targetVersion: plan.targetVersion,
    updatedAt: new Date().toISOString(),
    resolvedIds
  });

  return redact({
    schemaVersion: 1,
    ok: true,
    mode: "apply",
    transport: "live",
    stage: options.stage,
    appId: plan.appId,
    targetVersion: plan.targetVersion,
    executedRequestCount,
    executedUploadOperationCount: uploadOperationCount,
    resolvedIds,
    traceArtifact,
    stateArtifact: options.statePath
  });
}

function validatePlan(plan) {
  if (plan.mode !== "dry-run") throw new Error("mutation executor requires a dry-run plan");
  if (Array.isArray(plan.blockers) && plan.blockers.length > 0) {
    const codes = plan.blockers.map((blocker) => blocker.code).filter(Boolean).join(",");
    throw new Error(`refusing to apply plan with blockers: ${codes}`);
  }
  const ids = (plan.requests ?? []).map((request) => request.id);
  for (const required of ["create-review-submission-item", "submit-review-submission"]) {
    if (!ids.includes(required)) throw new Error(`refusing to apply plan without ${required}`);
  }
}

function stageRequestIds(stage, plan) {
  const screenshotRequestIds = (plan.requests ?? [])
    .map((request) => request.id)
    .filter((id) => /^reserve-screenshot-|^upload-screenshot-|^commit-screenshot-/.test(id));
  const stages = {
    "version-graph": [
      "fetch-target-app-store-version",
      "create-target-app-store-version",
      "fetch-version-localizations",
      "create-version-localization",
      "fetch-app-review-detail",
      "fetch-desktop-screenshot-set",
      "create-desktop-screenshot-set",
      "create-review-submission"
    ],
    metadata: [
      "fetch-app-infos",
      "fetch-app-info-localizations",
      "update-app-info-localization",
      "update-app-category",
      "update-version-localization",
      "fetch-app-review-detail",
      "update-app-review-detail"
    ],
    screenshots: [
      "fetch-desktop-screenshot-set",
      "create-desktop-screenshot-set",
      ...screenshotRequestIds
    ],
    "build-review": [
      "associate-processed-build",
      "create-review-submission",
      "create-review-submission-item"
    ],
    "final-submit": [
      "submit-review-submission"
    ]
  };
  if (!stages[stage]) throw new Error(`unknown live mutation stage: ${stage}`);
  return stages[stage];
}

function validateLivePreflight(plan, preflight, stage) {
  const errors = [];
  if (preflight.appId !== plan.appId) errors.push(`preflight app id ${preflight.appId} did not match plan app ${plan.appId}`);
  if (preflight.bundleId !== plan.bundleId) errors.push(`preflight bundle id ${preflight.bundleId} did not match plan bundle ${plan.bundleId}`);
  if (preflight.teamId !== plan.teamId) errors.push(`preflight team id ${preflight.teamId} did not match plan team ${plan.teamId}`);
  if (preflight.targetVersion !== plan.targetVersion) {
    errors.push(`preflight target version ${preflight.targetVersion} did not match plan target ${plan.targetVersion}`);
  }

  const plannedBuildId = plannedProcessedBuildId(plan);
  const uploadedBuild = preflight.uploadedBuild ?? {};
  if (plannedBuildId && uploadedBuild.id !== plannedBuildId) {
    errors.push(`preflight uploaded build id ${uploadedBuild.id} did not match plan build ${plannedBuildId}`);
  }
  if (uploadedBuild.version !== plan.targetVersion) {
    errors.push(`preflight uploaded build version ${uploadedBuild.version} did not match target ${plan.targetVersion}`);
  }
  if (uploadedBuild.processingState !== "VALID") {
    errors.push(`preflight uploaded build processing state ${uploadedBuild.processingState} is not VALID`);
  }
  if (uploadedBuild.expired === true) {
    errors.push("preflight uploaded build is expired");
  }

  const appInfoId = plannedAppInfoId(plan);
  if (appInfoId && preflight.appInfo?.id !== appInfoId) {
    errors.push(`preflight app info id ${preflight.appInfo?.id} did not match plan app info ${appInfoId}`);
  }
  if (stage === "version-graph" && preflight.targetAppStoreVersionExists === true && !preflight.targetAppStoreVersionIds?.length) {
    errors.push("preflight says target version exists but provided no targetAppStoreVersionIds");
  }
  if (stage === "final-submit" && !hasOldRejectionThreadReplyHandling(preflight)) {
    errors.push("final submit requires old rejection-thread reply handling status ui-reply-posted or ui-reply-unavailable-review-notes-used");
  }

  if (errors.length > 0) throw new Error(errors.join("; "));
}

function hasOldRejectionThreadReplyHandling(preflight) {
  const status = preflight.existingRejectionThread?.replyHandling?.status;
  return ["ui-reply-posted", "ui-reply-unavailable-review-notes-used"].includes(status);
}

function validateResolvedState(plan, preflight, state, stage) {
  const ids = state.resolvedIds ?? {};
  const missingRequiredIds = requiredResolvedStateIds(stage).filter((key) => !ids[key]);
  if (missingRequiredIds.length > 0) {
    throw new Error(`state missing required resolved ids for ${stage}: ${missingRequiredIds.join(",")}`);
  }

  const staleIds = new Set(plan.staleRejectedVersionIds ?? []);
  for (const [key, value] of Object.entries(ids)) {
    if (staleIds.has(value) && !isOwnedByPreflight(key, value, preflight)) {
      throw new Error(`state contains stale rejected App Store Connect id for ${key}: ${value}`);
    }
  }

  const targetIds = preflight.targetAppStoreVersionIds ?? [];
  if (ids.targetAppStoreVersionId) {
    if (targetIds.length === 0 || !targetIds.includes(ids.targetAppStoreVersionId)) {
      throw new Error(`state targetAppStoreVersionId ${ids.targetAppStoreVersionId} is not owned by preflight target ids`);
    }
  }

  const appInfoLocalizationIds = new Set((preflight.appInfoLocalizations ?? []).map((item) => item.id).filter(Boolean));
  if (ids.appInfoLocalizationId) {
    if (appInfoLocalizationIds.size === 0 || !appInfoLocalizationIds.has(ids.appInfoLocalizationId)) {
      throw new Error(`state appInfoLocalizationId ${ids.appInfoLocalizationId} is not owned by preflight app info localizations`);
    }
  }

  for (const key of [
    "appStoreVersionLocalizationId",
    "appStoreReviewDetailId",
    "appScreenshotSetId",
    "reviewSubmissionId",
    "reviewSubmissionItemId"
  ]) {
    if (ids[key]) {
      if (!preflight[key] || ids[key] !== preflight[key]) {
        throw new Error(`state ${key} ${ids[key]} is not owned by preflight`);
      }
    }
  }
}

function requiredResolvedStateIds(stage) {
  if (stage === "version-graph") return [];
  const versionGraphIds = [
    "targetAppStoreVersionId",
    "appStoreVersionLocalizationId",
    "appStoreReviewDetailId",
    "appScreenshotSetId",
    "reviewSubmissionId"
  ];
  if (stage === "final-submit") return [...versionGraphIds, "reviewSubmissionItemId"];
  return versionGraphIds;
}

function isOwnedByPreflight(key, value, preflight) {
  if (key === "targetAppStoreVersionId") {
    return (preflight.targetAppStoreVersionIds ?? []).includes(value);
  }
  if (key === "appInfoLocalizationId") {
    return (preflight.appInfoLocalizations ?? []).some((item) => item?.id === value);
  }
  return preflight[key] === value;
}

function plannedProcessedBuildId(plan) {
  const request = (plan.requests ?? []).find((candidate) => candidate.id === "associate-processed-build");
  return request?.body?.data?.id;
}

function plannedAppInfoId(plan) {
  const request = (plan.requests ?? []).find((candidate) => candidate.id === "update-app-category");
  const match = request?.path?.match(/^\/v1\/appInfos\/([^/]+)$/);
  return match?.[1]?.startsWith("${") ? undefined : match?.[1];
}

function shouldSkipCreateRequest(request, context) {
  const createIdMap = {
    "create-target-app-store-version": "targetAppStoreVersionId",
    "create-version-localization": "appStoreVersionLocalizationId",
    "create-app-info-localization": "appInfoLocalizationId",
    "create-desktop-screenshot-set": "appScreenshotSetId",
    "create-review-submission": "reviewSubmissionId",
    "create-review-submission-item": "reviewSubmissionItemId"
  };
  if (createIdMap[request.id] && context.ids[createIdMap[request.id]]) return true;
  if (request.id.startsWith("reserve-screenshot-")) {
    const screenshotKey = request.id.replace(/^reserve-screenshot-/, "");
    return Boolean(context.ids[`appScreenshotId:${screenshotKey}`]);
  }
  return false;
}

async function executeLiveUploadOperations(request, resolvedRequest, context) {
  const sourceResponse = context.responses[request.dependsOn];
  const operations = sourceResponse?.data?.attributes?.uploadOperations;
  if (!Array.isArray(operations) || operations.length === 0) {
    throw new Error(`missing upload operations for ${request.id}`);
  }
  const reviewed = verifyReviewedScreenshotFile(resolvedRequest);
  const bytes = reviewed.bytes;
  const events = [];
  for (const operation of operations) {
    const offset = Number.isInteger(operation.offset) ? operation.offset : 0;
    const length = Number.isInteger(operation.length) ? operation.length : bytes.length - offset;
    const body = bytes.subarray(offset, offset + length);
    const response = await fetch(operation.url, {
      method: operation.method,
      headers: uploadHeaders(operation),
      body
    });
    if (!response.ok) {
      throw new Error(`upload operation for ${request.id} failed with status ${response.status}`);
    }
    events.push({
      kind: "upload",
      requestId: request.id,
      method: operation.method,
      url: "[REDACTED_UPLOAD_URL]",
      status: response.status,
      filePath: resolvedRequest.filePath,
      fileSize: reviewed.fileSize,
      sourceFileChecksum: reviewed.sourceFileChecksum
    });
  }
  return events;
}

function uploadHeaders(operation) {
  const headers = {};
  const requestHeaders = operation.requestHeaders ?? operation.headers ?? [];
  if (Array.isArray(requestHeaders)) {
    for (const header of requestHeaders) {
      if (header?.name && header?.value !== undefined) headers[header.name] = String(header.value);
    }
  } else if (requestHeaders && typeof requestHeaders === "object") {
    Object.assign(headers, requestHeaders);
  }
  return headers;
}

function responseSummary(response) {
  if (Array.isArray(response?.data)) {
    return {
      dataCount: response.data.length,
      ids: response.data.map((item) => item?.id).filter(Boolean),
      types: [...new Set(response.data.map((item) => item?.type).filter(Boolean))]
    };
  }
  return {
    id: response?.data?.id,
    type: response?.data?.type,
    attributes: response?.data?.attributes ? summarizeAttributes(response.data.attributes) : undefined
  };
}

function summarizeAttributes(attributes) {
  const allowed = {};
  for (const key of ["versionString", "locale", "screenshotDisplayType", "state", "processingState"]) {
    if (attributes[key] !== undefined) allowed[key] = attributes[key];
  }
  return allowed;
}

function readState(path) {
  if (!path || !fs.existsSync(path)) return { resolvedIds: {} };
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function writeState(path, state) {
  fs.mkdirSync(dirname(path), { recursive: true });
  fs.writeFileSync(path, `${JSON.stringify(state, null, 2)}\n`);
}

function loadAscConfig(configPath) {
  const resolved = configPath ?? join(homedir(), "Library/Application Support/AppleDistributionKit/app-store-connect/config.json");
  const config = JSON.parse(fs.readFileSync(resolved, "utf8"));
  return {
    issuerId: config.issuerId,
    keyId: config.keyId,
    privateKeyPem: fs.readFileSync(config.privateKeyPath, "utf8")
  };
}

function createAscClient(config) {
  return {
    request: async ({ method, path, query, body }) => {
      const url = new URL(path, "https://api.appstoreconnect.apple.com");
      Object.entries(query ?? {}).forEach(([key, value]) => url.searchParams.set(key, value));
      const headers = {
        Accept: "application/json",
        Authorization: `Bearer ${signJwt(config)}`
      };
      if (body !== undefined) headers["Content-Type"] = "application/json";
      const response = await fetch(url, {
        method,
        headers,
        ...(body !== undefined ? { body: JSON.stringify(body) } : {})
      });
      return parseAscResponse(response);
    }
  };
}

async function parseAscResponse(response) {
  const text = await response.text();
  const parsed = text.trim() ? JSON.parse(text) : { ok: true };
  if (!response.ok) {
    const first = Array.isArray(parsed?.errors) ? parsed.errors[0] : undefined;
    const title = first?.title ?? first?.detail ?? "App Store Connect request failed";
    throw new Error(`App Store Connect ${response.status}: ${title}`);
  }
  return parsed;
}

function signJwt(config) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: config.keyId, typ: "JWT" };
  const payload = { iss: config.issuerId, iat: now, exp: now + 20 * 60, aud: "appstoreconnect-v1" };
  const signingInput = `${base64Url(JSON.stringify(header))}.${base64Url(JSON.stringify(payload))}`;
  const signature = sign("sha256", Buffer.from(signingInput), {
    key: createPrivateKey(config.privateKeyPem),
    dsaEncoding: "ieee-p1363"
  });
  return `${signingInput}.${base64Url(signature)}`;
}

function base64Url(input) {
  return Buffer.from(input).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function executeUploadOperations(request, resolvedRequest, transport, context) {
  const sourceResponse = transport.responses?.[request.dependsOn];
  const operations = sourceResponse?.data?.attributes?.uploadOperations;
  if (!Array.isArray(operations) || operations.length === 0) {
    throw new Error(`missing upload operations for ${request.id}`);
  }
  const screenshot = context.screenshots.find((candidate, index) => {
    const ordinal = String(index + 1).padStart(2, "0");
    return request.id.endsWith(`${ordinal}-${candidate.scene}`);
  });
  const reviewed = verifyReviewedScreenshotFile(resolvedRequest);
  return operations.map((operation) => redact({
    kind: "upload",
    requestId: request.id,
    method: operation.method,
    url: operation.url,
    filePath: resolvedRequest.filePath,
    fileSize: reviewed.fileSize ?? screenshot?.fileSize,
    sourceFileChecksum: reviewed.sourceFileChecksum ?? screenshot?.sourceFileChecksum
  }));
}

function verifyReviewedScreenshotFile(resolvedRequest) {
  const bytes = fs.readFileSync(resolvedRequest.filePath);
  const fileSize = bytes.length;
  const sourceFileChecksum = createHash("md5").update(bytes).digest("hex");
  if (resolvedRequest.fileSize !== undefined && fileSize !== resolvedRequest.fileSize) {
    throw new Error(`screenshot file changed since dry-run: ${resolvedRequest.filePath}`);
  }
  if (resolvedRequest.sourceFileChecksum && sourceFileChecksum !== resolvedRequest.sourceFileChecksum) {
    throw new Error(`screenshot file changed since dry-run: ${resolvedRequest.filePath}`);
  }
  return { bytes, fileSize, sourceFileChecksum };
}

function captureIds(request, response, context) {
  if (Array.isArray(response?.data)) {
    if (request.id === "fetch-version-localizations") {
      const localization = response.data.find((item) => item?.attributes?.locale === "en-US") ?? response.data[0];
      captureResourceId(request, localization, context);
      return;
    }
    if (request.id === "fetch-app-info-localizations") {
      const localization = response.data.find((item) => item?.attributes?.locale === "en-US") ?? response.data[0];
      captureResourceId(request, localization, context);
      return;
    }
    if (request.id === "fetch-desktop-screenshot-set") {
      const set = response.data.find((item) => item?.attributes?.screenshotDisplayType === "APP_DESKTOP");
      captureResourceId(request, set, context);
      return;
    }
    for (const item of response.data) captureResourceId(request, item, context);
    return;
  }
  captureResourceId(request, response?.data, context);
}

function captureResourceId(request, data, context) {
  const id = data?.id;
  if (!id) return;
  const type = data?.type;
  if (request.id === "fetch-target-app-store-version" || request.id === "create-target-app-store-version" || type === "appStoreVersions") {
    context.ids.targetAppStoreVersionId = id;
  } else if (request.id === "fetch-version-localizations" || request.id === "create-version-localization" || type === "appStoreVersionLocalizations") {
    context.ids.appStoreVersionLocalizationId = id;
  } else if (request.id === "fetch-app-info-localizations" || request.id === "create-app-info-localization" || type === "appInfoLocalizations") {
    context.ids.appInfoLocalizationId = id;
  } else if (request.id === "fetch-app-review-detail" || type === "appStoreReviewDetails") {
    context.ids.appStoreReviewDetailId = id;
  } else if (request.id === "create-desktop-screenshot-set" || type === "appScreenshotSets") {
    context.ids.appScreenshotSetId = id;
  } else if (request.id.startsWith("reserve-screenshot-") || type === "appScreenshots") {
    const screenshotKey = request.id.replace(/^reserve-screenshot-/, "");
    context.ids[`appScreenshotId:${screenshotKey}`] = id;
  } else if (request.id === "create-review-submission" || type === "reviewSubmissions") {
    context.ids.reviewSubmissionId = id;
  } else if (request.id === "create-review-submission-item" || type === "reviewSubmissionItems") {
    context.ids.reviewSubmissionItemId = id;
  }
}

function publicResolvedIds(context) {
  const output = {};
  for (const key of [
    "targetAppStoreVersionId",
    "appStoreVersionLocalizationId",
    "appInfoLocalizationId",
    "appStoreReviewDetailId",
    "appScreenshotSetId",
    "reviewSubmissionId",
    "reviewSubmissionItemId"
  ]) {
    if (context.ids[key]) output[key] = context.ids[key];
  }
  return output;
}

function resolveValue(value, context) {
  if (Array.isArray(value)) return value.map((item) => resolveValue(item, context));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, resolveValue(child, context)]));
  }
  if (typeof value !== "string") return value;
  return value.replace(/\$\{([^}]+)\}/g, (match, key) => context.ids[key] ?? match);
}

function assertNoUnresolvedPlaceholders(requestId, value) {
  const serialized = JSON.stringify(value);
  if (serialized.includes("${")) {
    throw new Error(`unresolved placeholder before executing ${requestId}`);
  }
}

function isRetryableStatus(status) {
  return [429, 500, 502, 503, 504].includes(Number(status));
}

function redact(value, key = "") {
  if (Array.isArray(value)) return value.map((item) => redact(item));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([childKey, child]) => [childKey, redact(child, childKey)]));
  }
  if (typeof value === "string" && (isSensitiveKey(key) || /Bearer\s+|eyJ[A-Za-z0-9_-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(value))) {
    return "[REDACTED_SECRET]";
  }
  return value;
}

function isSensitiveKey(key) {
  return /token|secret|password|authorization|private|api[_-]?key|keyId|issuer/i.test(key);
}

function redactText(text) {
  return text
    .replace(/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, "[REDACTED_SECRET]")
    .replace(/Bearer\s+[A-Za-z0-9._-]+/g, "Bearer [REDACTED_SECRET]")
    .replace(/eyJ[A-Za-z0-9._-]+/g, "[REDACTED_SECRET]")
    .replace(/AuthKey_[A-Za-z0-9]+\.p8/g, "AuthKey_[REDACTED].p8");
}

function writeOutput(summary, options) {
  if (!summary) return;
  const body = options.json ? `${JSON.stringify(summary, null, 2)}\n` : textSummary(summary);
  process.stdout.write(body);
}

function textSummary(summary) {
  return [
    `Applied ${summary.executedRequestCount} planned requests with ${summary.executedUploadOperationCount} upload operations`,
    `Target ${summary.appId} ${summary.targetVersion}`
  ].join("\n") + "\n";
}

try {
  const options = parseArgs(process.argv.slice(2));
  writeOutput(await applyPlan(options), options);
} catch (error) {
  process.stderr.write(`error: ${redactText(error instanceof Error ? error.message : String(error))}\n`);
  process.exit(1);
}
