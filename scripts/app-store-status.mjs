#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import { dirname } from "node:path";

const DEFAULTS = {
  appId: "6787262892",
  bundleId: "bot.ouro.md",
  teamId: "743GT2AJ24",
  rejectedAuditVersionString: "0.9.79",
  versionId: "7309944f-cbe8-4518-960c-444e6116ab46",
  reviewSubmissionId: "b37f847e-0ecb-4e7a-bb00-14e3038b0f4c"
};

function parseArgs(argv) {
  const options = {
    appId: DEFAULTS.appId,
    bundleId: DEFAULTS.bundleId,
    teamId: DEFAULTS.teamId,
    versionId: undefined,
    reviewSubmissionId: undefined,
    useRejectedAuditDefaults: false,
    json: false,
    selftest: false,
    selftestMissingFields: false,
    selftestPrivateKeyError: false,
    selftestFirstItemUnrelated: false,
    selftestReviewItemMismatch: false,
    selftestMissingScreenshotState: false,
    selftestFailedScreenshotState: false,
    selftestNonDesktopScreenshotSet: false
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--selftest") options.selftest = true;
    else if (arg === "--selftest-missing-fields") options.selftestMissingFields = true;
    else if (arg === "--selftest-private-key-error") options.selftestPrivateKeyError = true;
    else if (arg === "--selftest-first-item-unrelated") options.selftestFirstItemUnrelated = true;
    else if (arg === "--selftest-review-item-mismatch") options.selftestReviewItemMismatch = true;
    else if (arg === "--selftest-missing-screenshot-state") options.selftestMissingScreenshotState = true;
    else if (arg === "--selftest-failed-screenshot-state") options.selftestFailedScreenshotState = true;
    else if (arg === "--selftest-non-desktop-screenshot-set") options.selftestNonDesktopScreenshotSet = true;
    else if (arg === "--use-rejected-audit-defaults") options.useRejectedAuditDefaults = true;
    else if (arg === "--app-id") options.appId = argv[++index];
    else if (arg === "--bundle-id") options.bundleId = argv[++index];
    else if (arg === "--team-id") options.teamId = argv[++index];
    else if (arg === "--version-id") options.versionId = argv[++index];
    else if (arg === "--review-submission-id") options.reviewSubmissionId = argv[++index];
    else if (arg === "--config") options.configPath = argv[++index];
    else if (arg === "--artifact") options.artifactPath = argv[++index];
    else if (arg === "--json") options.json = true;
    else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }

  return finalizeOptions(options);
}

function finalizeOptions(options) {
  if (options.useRejectedAuditDefaults) {
    if (options.versionId || options.reviewSubmissionId) {
      throw new Error("--use-rejected-audit-defaults cannot be combined with --version-id or --review-submission-id");
    }
    options.versionId = DEFAULTS.versionId;
    options.reviewSubmissionId = DEFAULTS.reviewSubmissionId;
    options.statusPurpose = "rejected-audit";
    options.usedRejectedAuditDefaults = true;
    return options;
  }

  if (options.selftest) {
    options.versionId = options.versionId ?? DEFAULTS.versionId;
    options.reviewSubmissionId = options.reviewSubmissionId ?? DEFAULTS.reviewSubmissionId;
    options.statusPurpose = "selftest";
    options.usedRejectedAuditDefaults = false;
    return options;
  }

  if (!options.versionId || !options.reviewSubmissionId) {
    throw new Error("live status requires --version-id and --review-submission-id, or --use-rejected-audit-defaults for the rejected 0.9.79 audit snapshot");
  }

  options.statusPurpose = "submission-readiness";
  options.usedRejectedAuditDefaults = false;
  return options;
}

function normalizeStatus(responses, options) {
  const app = singleResource(responses.app, "app");
  const version = singleResource(responses.version, "app store version");
  const localizations = resourceArray(responses.localizations, "app store version localizations");
  const localization = localizations.find((item) => item.attributes?.locale === "en-US") ?? localizations[0];
  const reviewDetail = singleResource(responses.reviewDetail, "app store review detail");
  const build = singleResource(responses.build, "build");
  const screenshotSets = resourceArray(responses.screenshotSets, "app screenshot sets");
  const screenshotSet = screenshotSets.find((item) => item.attributes?.screenshotDisplayType === "APP_DESKTOP");
  if (!screenshotSet) throw new Error("missing required field: APP_DESKTOP screenshot set");
  const screenshots = resourceArray(responses.screenshots, "app screenshots");
  const reviewSubmission = singleResource(responses.reviewSubmission, "review submission");
  const reviewSubmissionItems = resourceArray(responses.reviewSubmissionItems, "review submission items");
  const matchingReviewSubmissionItems = reviewSubmissionItems.filter((item) => (
    item.relationships?.appStoreVersion?.data?.id === version.id
  ));
  if (matchingReviewSubmissionItems.length === 0) {
    throw new Error(`no review submission item matched app store version ${version.id}`);
  }
  if (matchingReviewSubmissionItems.length > 1) {
    throw new Error(`multiple review submission items matched app store version ${version.id}`);
  }
  const reviewSubmissionItem = matchingReviewSubmissionItems[0];
  const reviewSubmissionItemAppStoreVersionId = reviewSubmissionItem.relationships?.appStoreVersion?.data?.id;
  const screenshotDeliveryStates = screenshots.map((screenshot) => screenshot.attributes?.assetDeliveryState?.state ?? null);

  const summary = {
    schemaVersion: 1,
    capturedAt: new Date().toISOString(),
    statusPurpose: options.statusPurpose,
    usedRejectedAuditDefaults: options.usedRejectedAuditDefaults,
    rejectedAuditDefaultVersionString: options.usedRejectedAuditDefaults ? DEFAULTS.rejectedAuditVersionString : null,
    appId: app.id,
    bundleId: app.attributes?.bundleId,
    teamId: options.teamId,
    appName: app.attributes?.name,
    currentAppStoreVersionId: version.id,
    currentVersionString: version.attributes?.versionString,
    currentVersionState: version.attributes?.appStoreState ?? version.attributes?.appVersionState,
    appStoreVersionLocalizationId: localization?.id,
    locale: localization?.attributes?.locale,
    reviewDetailId: reviewDetail.id,
    reviewSubmissionId: reviewSubmission.id,
    reviewSubmissionState: reviewSubmission.attributes?.state,
    reviewSubmissionItemId: reviewSubmissionItem?.id,
    reviewSubmissionItemAppStoreVersionId,
    reviewSubmissionItemState: reviewSubmissionItem?.attributes?.state,
    buildId: build.id,
    buildVersion: build.attributes?.version,
    buildProcessingState: build.attributes?.processingState,
    screenshotSetId: screenshotSet?.id,
    screenshotDisplayType: screenshotSet?.attributes?.screenshotDisplayType,
    screenshotCount: screenshots.length,
    screenshotIds: screenshots.map((screenshot) => screenshot.id),
    screenshotDeliveryStates
  };

  validateSummary(summary, options);
  return redact(summary);
}

function validateSummary(summary, options) {
  const required = {
    appId: summary.appId,
    statusPurpose: summary.statusPurpose,
    bundleId: summary.bundleId,
    teamId: summary.teamId,
    currentAppStoreVersionId: summary.currentAppStoreVersionId,
    currentVersionString: summary.currentVersionString,
    currentVersionState: summary.currentVersionState,
    appStoreVersionLocalizationId: summary.appStoreVersionLocalizationId,
    reviewDetailId: summary.reviewDetailId,
    reviewSubmissionId: summary.reviewSubmissionId,
    reviewSubmissionState: summary.reviewSubmissionState,
    reviewSubmissionItemAppStoreVersionId: summary.reviewSubmissionItemAppStoreVersionId,
    reviewSubmissionItemState: summary.reviewSubmissionItemState,
    buildId: summary.buildId,
    buildProcessingState: summary.buildProcessingState,
    screenshotSetId: summary.screenshotSetId,
    screenshotDisplayType: summary.screenshotDisplayType
  };

  for (const [field, value] of Object.entries(required)) {
    if (value === undefined || value === null || value === "") {
      throw new Error(`missing required field: ${field}`);
    }
  }
  if (summary.appId !== options.appId) throw new Error(`unexpected app id: ${summary.appId}`);
  if (summary.bundleId !== options.bundleId) throw new Error(`unexpected bundle id: ${summary.bundleId}`);
  if (summary.teamId !== options.teamId) throw new Error(`unexpected team id: ${summary.teamId}`);
  if (summary.screenshotDisplayType !== "APP_DESKTOP") throw new Error(`unexpected screenshot display type: ${summary.screenshotDisplayType}`);
  if (summary.screenshotCount < 1) throw new Error("missing required field: screenshotCount");
  if (!Array.isArray(summary.screenshotDeliveryStates)
    || summary.screenshotDeliveryStates.length !== summary.screenshotCount
    || summary.screenshotDeliveryStates.some((state) => state === undefined || state === null || state === "")) {
    throw new Error("missing required field: screenshotDeliveryStates");
  }
  const invalidScreenshotStates = summary.screenshotDeliveryStates.filter((state) => state !== "COMPLETE");
  if (invalidScreenshotStates.length > 0) {
    throw new Error(`unexpected screenshot delivery state: ${invalidScreenshotStates.join(",")}`);
  }
}

function singleResource(response, label) {
  const data = response?.data;
  if (!data || Array.isArray(data)) throw new Error(`missing required field: ${label}.data`);
  return data;
}

function resourceArray(response, label) {
  const data = response?.data;
  if (!Array.isArray(data)) throw new Error(`missing required field: ${label}.data`);
  return data;
}

function redact(value, key = "") {
  if (Array.isArray(value)) return value.map((item) => redact(item));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([childKey, child]) => [childKey, redact(child, childKey)]));
  }
  if (typeof value === "string") {
    if (isSensitiveKey(key) || /-----BEGIN [A-Z ]*PRIVATE KEY-----|Bearer\s+|eyJ[A-Za-z0-9_-]{10,}/.test(value)) {
      return "[REDACTED_SECRET]";
    }
  }
  return value;
}

function isSensitiveKey(key) {
  return /token|secret|password|authorization|private|key/i.test(key);
}

function ascGet(path, options) {
  const args = ["./scripts/apple-distribution-kit.sh", "asc", "get", "--path", path, "--json"];
  for (const query of options.query ?? []) args.push("--query", query);
  if (options.configPath) args.push("--config", options.configPath);
  const result = spawnSync(args[0], args.slice(1), { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(redactText(result.stderr || result.stdout || `asc get failed for ${path}`));
  }
  const parsed = JSON.parse(result.stdout);
  return parsed.result;
}

function redactText(text) {
  return text
    .replace(/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, "[REDACTED_SECRET]")
    .replace(/Bearer\s+[A-Za-z0-9._-]+/g, "Bearer [REDACTED_SECRET]")
    .replace(/eyJ[A-Za-z0-9._-]+/g, "[REDACTED_SECRET]")
    .replace(/AuthKey_[A-Za-z0-9]+\.p8/g, "AuthKey_[REDACTED].p8");
}

function fetchLiveStatus(options) {
  const app = ascGet(`/v1/apps/${options.appId}`, options);
  const version = ascGet(`/v1/appStoreVersions/${options.versionId}`, options);
  const localizations = ascGet(`/v1/appStoreVersions/${options.versionId}/appStoreVersionLocalizations`, options);
  const localization = resourceArray(localizations, "app store version localizations").find((item) => item.attributes?.locale === "en-US")
    ?? resourceArray(localizations, "app store version localizations")[0];
  if (!localization?.id) throw new Error("missing required field: appStoreVersionLocalizationId");
  const reviewDetail = ascGet(`/v1/appStoreVersions/${options.versionId}/appStoreReviewDetail`, options);
  const build = ascGet(`/v1/appStoreVersions/${options.versionId}/build`, options);
  const screenshotSets = ascGet(`/v1/appStoreVersionLocalizations/${localization.id}/appScreenshotSets`, options);
  const screenshotSet = resourceArray(screenshotSets, "app screenshot sets").find((item) => item.attributes?.screenshotDisplayType === "APP_DESKTOP");
  if (!screenshotSet?.id) throw new Error("missing required field: APP_DESKTOP screenshot set");
  const screenshots = ascGet(`/v1/appScreenshotSets/${screenshotSet.id}/appScreenshots`, options);
  const reviewSubmission = ascGet(`/v1/reviewSubmissions/${options.reviewSubmissionId}`, options);
  const reviewSubmissionItems = ascGet(`/v1/reviewSubmissions/${options.reviewSubmissionId}/items`, {
    ...options,
    query: ["include=appStoreVersion"]
  });
  return { app, version, localizations, reviewDetail, build, screenshotSets, screenshots, reviewSubmission, reviewSubmissionItems };
}

function fixtureResponses() {
  return {
    app: {
      data: {
        type: "apps",
        id: DEFAULTS.appId,
        attributes: { name: "Ouro MD", bundleId: DEFAULTS.bundleId }
      }
    },
    version: {
      data: {
        type: "appStoreVersions",
        id: DEFAULTS.versionId,
        attributes: { versionString: "0.9.79", appStoreState: "REJECTED" }
      }
    },
    localizations: {
      data: [
        {
          type: "appStoreVersionLocalizations",
          id: "5dca4b0b-3e0d-4913-acbd-b172f6c1bacb",
          attributes: { locale: "en-US", promotionalText: "token-looking eyJsecret" }
        }
      ]
    },
    reviewDetail: {
      data: {
        type: "appStoreReviewDetails",
        id: "3bc7284e-27d5-4dd3-a049-b9e859289bd1",
        attributes: { demoAccountPassword: "PRIVATE KEY should not leak" }
      }
    },
    build: {
      data: {
        type: "builds",
        id: "2f55e88f-a05b-4065-a4b5-4e55180d8835",
        attributes: { version: "0.9.79", processingState: "VALID", iconAssetToken: { templateUrl: "secret" } }
      }
    },
    screenshotSets: {
      data: [
        {
          type: "appScreenshotSets",
          id: "f37ecb51-c96e-451d-9b29-20d86d7f118e",
          attributes: { screenshotDisplayType: "APP_DESKTOP" }
        }
      ]
    },
    screenshots: {
      data: [
        {
          type: "appScreenshots",
          id: "80a8620a-643a-46bd-9e39-ab19f26ba424",
          attributes: {
            assetToken: "Bearer secret",
            assetDeliveryState: { state: "COMPLETE" }
          }
        }
      ]
    },
    reviewSubmission: {
      data: {
        type: "reviewSubmissions",
        id: DEFAULTS.reviewSubmissionId,
        attributes: { state: "UNRESOLVED_ISSUES" }
      }
    },
    reviewSubmissionItems: {
      data: [
        {
          type: "reviewSubmissionItems",
          id: "YjM3Zjg0N2UtMGVjYi00ZTdhLWJiMDAtMTRlMzAzOGIwZjRjfDZ8ODg3ODEyNjgx",
          attributes: { state: "REJECTED" },
          relationships: {
            appStoreVersion: {
              data: { type: "appStoreVersions", id: DEFAULTS.versionId }
            }
          }
        }
      ]
    }
  };
}

function runSelftest(options) {
  const responses = fixtureResponses();
  if (options.selftestPrivateKeyError) {
    const pem = "-----BEGIN " + "PRIVATE KEY-----\nabc123\n-----END " + "PRIVATE KEY-----";
    throw new Error(`simulated credential failure: ${pem} Bearer token`);
  }
  if (options.selftestMissingFields) {
    delete responses.app.data.attributes.bundleId;
  }
  if (options.selftestFirstItemUnrelated) {
    responses.reviewSubmissionItems.data[0].id = "matching-item";
    responses.reviewSubmissionItems.data.unshift({
      type: "reviewSubmissionItems",
      id: "unrelated-item",
      attributes: { state: "ACCEPTED" },
      relationships: {
        appStoreVersion: {
          data: { type: "appStoreVersions", id: "unrelated-version" }
        }
      }
    });
  }
  if (options.selftestReviewItemMismatch) {
    responses.reviewSubmissionItems.data[0].relationships.appStoreVersion.data.id = "unrelated-version";
  }
  if (options.selftestMissingScreenshotState) {
    delete responses.screenshots.data[0].attributes.assetDeliveryState;
  }
  if (options.selftestFailedScreenshotState) {
    responses.screenshots.data[0].attributes.assetDeliveryState.state = "FAILED";
  }
  if (options.selftestNonDesktopScreenshotSet) {
    responses.screenshotSets.data[0].attributes.screenshotDisplayType = "APP_IPHONE_65";
  }
  return normalizeStatus(responses, options);
}

function writeOutput(summary, options) {
  const body = options.json ? `${JSON.stringify(summary, null, 2)}\n` : textSummary(summary);
  if (options.artifactPath) {
    fs.mkdirSync(dirname(options.artifactPath), { recursive: true });
    fs.writeFileSync(options.artifactPath, body);
  }
  process.stdout.write(body);
}

function textSummary(summary) {
  const purpose = summary.usedRejectedAuditDefaults
    ? `Purpose ${summary.statusPurpose}; using rejected ${summary.rejectedAuditDefaultVersionString} defaults`
    : `Purpose ${summary.statusPurpose}`;
  return [
    purpose,
    `App ${summary.appId} (${summary.bundleId}) on team ${summary.teamId}`,
    `Version ${summary.currentVersionString} ${summary.currentVersionState} (${summary.currentAppStoreVersionId})`,
    `Build ${summary.buildVersion} ${summary.buildProcessingState} (${summary.buildId})`,
    `Review submission ${summary.reviewSubmissionState}; item ${summary.reviewSubmissionItemState} (${summary.reviewSubmissionId})`,
    `Screenshots ${summary.screenshotCount} ${summary.screenshotDisplayType} ${summary.screenshotDeliveryStates.join(",")} (${summary.screenshotSetId})`
  ].join("\n") + "\n";
}

try {
  const options = parseArgs(process.argv.slice(2));
  const summary = options.selftest
    ? runSelftest(options)
    : normalizeStatus(fetchLiveStatus(options), options);
  writeOutput(summary, options);
} catch (error) {
  process.stderr.write(`error: ${redactText(error instanceof Error ? error.message : String(error))}\n`);
  process.exit(1);
}
