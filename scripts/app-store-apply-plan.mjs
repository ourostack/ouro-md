#!/usr/bin/env node
import fs from "node:fs";
import { dirname, join } from "node:path";

function parseArgs(argv) {
  const options = { json: false };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--mode") options.mode = argv[++index];
    else if (arg === "--plan") options.planPath = argv[++index];
    else if (arg === "--transport-fixture") options.transportFixturePath = argv[++index];
    else if (arg === "--artifact-dir") options.artifactDir = argv[++index];
    else if (arg === "--json") options.json = true;
    else throw new Error(`unknown argument: ${arg}`);
  }
  return options;
}

function validateOptions(options) {
  if (options.mode !== "apply") throw new Error("mutation executor requires --mode apply");
  if (!options.planPath) throw new Error("mutation executor requires --plan <path>");
  if (!options.transportFixturePath) throw new Error("mutation executor requires --transport-fixture <path>");
  if (!options.artifactDir) throw new Error("mutation executor requires --artifact-dir <path>");
}

function applyPlan(options) {
  validateOptions(options);
  const plan = JSON.parse(fs.readFileSync(options.planPath, "utf8"));
  const transport = JSON.parse(fs.readFileSync(options.transportFixturePath, "utf8"));
  validatePlan(plan);
  fs.mkdirSync(options.artifactDir, { recursive: true });

  const context = { ids: {}, screenshots: plan.screenshots ?? [] };
  const events = [];
  let uploadOperationCount = 0;

  for (const request of plan.requests ?? []) {
    const resolvedRequest = resolveValue(request, context);
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
  return operations.map((operation) => redact({
    kind: "upload",
    requestId: request.id,
    method: operation.method,
    url: operation.url,
    filePath: resolvedRequest.filePath,
    fileSize: resolvedRequest.fileSize ?? screenshot?.fileSize,
    sourceFileChecksum: resolvedRequest.sourceFileChecksum ?? screenshot?.sourceFileChecksum
  }));
}

function captureIds(request, response, context) {
  const id = response?.data?.id;
  if (!id) return;
  const type = response?.data?.type;
  if (request.id === "create-target-app-store-version" || type === "appStoreVersions") {
    context.ids.targetAppStoreVersionId = id;
  } else if (request.id === "create-version-localization" || type === "appStoreVersionLocalizations") {
    context.ids.appStoreVersionLocalizationId = id;
  } else if (request.id === "create-app-info-localization" || type === "appInfoLocalizations") {
    context.ids.appInfoLocalizationId = id;
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
  writeOutput(applyPlan(options), options);
} catch (error) {
  process.stderr.write(`error: ${redactText(error instanceof Error ? error.message : String(error))}\n`);
  process.exit(1);
}
