#!/usr/bin/env node
import { createHash } from "node:crypto";
import fs from "node:fs";
import { basename, dirname } from "node:path";

const DEFAULTS = {
  appId: "6787262892",
  bundleId: "bot.ouro.md",
  teamId: "743GT2AJ24",
  channelId: "mac-app-store",
  platform: "MAC_OS",
  manifestPath: "distribution/apple-distribution.json",
  releasePath: "Sources/OuroMDCore/OuroMDRelease.swift",
  rejectedReviewSubmissionId: "b37f847e-0ecb-4e7a-bb00-14e3038b0f4c",
  staleRejectedIds: [
    "7309944f-cbe8-4518-960c-444e6116ab46",
    "5dca4b0b-3e0d-4913-acbd-b172f6c1bacb",
    "3bc7284e-27d5-4dd3-a049-b9e859289bd1",
    "f37ecb51-c96e-451d-9b29-20d86d7f118e",
    "80a8620a-643a-46bd-9e39-ab19f26ba424"
  ]
};

const PLACEHOLDERS = {
  targetAppStoreVersionId: "${targetAppStoreVersionId}",
  appStoreVersionLocalizationId: "${appStoreVersionLocalizationId}",
  appInfoId: "${appInfoId}",
  appInfoLocalizationId: "${appInfoLocalizationId}",
  appStoreReviewDetailId: "${appStoreReviewDetailId}",
  appScreenshotSetId: "${appScreenshotSetId}",
  processedBuildId: "${processedBuildId}",
  reviewSubmissionId: "${reviewSubmissionId}"
};

function parseArgs(argv) {
  const options = {
    mode: "dry-run",
    json: false,
    selftest: false,
    selftestStaleIds: false,
    manifestPath: DEFAULTS.manifestPath,
    releasePath: DEFAULTS.releasePath,
    channelId: DEFAULTS.channelId,
    appId: DEFAULTS.appId,
    bundleId: DEFAULTS.bundleId,
    teamId: DEFAULTS.teamId,
    platform: DEFAULTS.platform,
    targetVersionId: PLACEHOLDERS.targetAppStoreVersionId,
    appStoreVersionLocalizationId: PLACEHOLDERS.appStoreVersionLocalizationId,
    appInfoId: PLACEHOLDERS.appInfoId,
    appInfoLocalizationId: PLACEHOLDERS.appInfoLocalizationId,
    appStoreReviewDetailId: PLACEHOLDERS.appStoreReviewDetailId,
    appScreenshotSetId: PLACEHOLDERS.appScreenshotSetId,
    processedBuildId: PLACEHOLDERS.processedBuildId,
    reviewSubmissionId: PLACEHOLDERS.reviewSubmissionId,
    screenshots: []
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--json") options.json = true;
    else if (arg === "--selftest") options.selftest = true;
    else if (arg === "--selftest-stale-ids") options.selftestStaleIds = true;
    else if (arg === "--manifest") options.manifestPath = argv[++index];
    else if (arg === "--release-source") options.releasePath = argv[++index];
    else if (arg === "--channel-id") options.channelId = argv[++index];
    else if (arg === "--app-id") options.appId = argv[++index];
    else if (arg === "--bundle-id") options.bundleId = argv[++index];
    else if (arg === "--team-id") options.teamId = argv[++index];
    else if (arg === "--target-version-id") options.targetVersionId = argv[++index];
    else if (arg === "--version-localization-id") options.appStoreVersionLocalizationId = argv[++index];
    else if (arg === "--app-info-id") options.appInfoId = argv[++index];
    else if (arg === "--app-info-localization-id") options.appInfoLocalizationId = argv[++index];
    else if (arg === "--review-detail-id") options.appStoreReviewDetailId = argv[++index];
    else if (arg === "--screenshot-set-id") options.appScreenshotSetId = argv[++index];
    else if (arg === "--processed-build-id") options.processedBuildId = argv[++index];
    else if (arg === "--review-submission-id") options.reviewSubmissionId = argv[++index];
    else if (arg === "--screenshot") options.screenshots.push(argv[++index]);
    else if (arg === "--artifact") options.artifactPath = argv[++index];
    else throw new Error(`unknown argument: ${arg}`);
  }

  if (options.selftestStaleIds) {
    options.selftest = true;
    options.targetVersionId = DEFAULTS.staleRejectedIds[0];
  }
  return options;
}

function buildPlan(options) {
  if (options.mode !== "dry-run") throw new Error(`unsupported mode: ${options.mode}`);
  guardAgainstStaleTargetIds(options);

  const manifest = JSON.parse(fs.readFileSync(options.manifestPath, "utf8"));
  const channel = requireAppStoreChannel(manifest, options.channelId);
  const store = channel.store;
  const locale = manifest.app?.primaryLocale ?? "en-US";
  const targetVersion = store.version;
  const releaseNotes = readReleaseNotes(options.releasePath);
  const screenshots = options.selftest
    ? selftestScreenshots()
    : screenshotInputs(options.screenshots.length > 0 ? options.screenshots : store.screenshots ?? []);
  const screenshotReadiness = validateScreenshotReadiness(screenshots, store.screenshotRequirements);

  const context = {
    appId: options.appId,
    bundleId: options.bundleId,
    teamId: options.teamId,
    platform: options.platform,
    locale,
    targetVersion,
    store,
    releaseNotes,
    ids: options
  };

  return redact({
    schemaVersion: 1,
    mode: options.mode,
    generatedAt: new Date().toISOString(),
    appId: options.appId,
    bundleId: options.bundleId,
    teamId: options.teamId,
    platform: options.platform,
    targetVersion,
    locale,
    staleRejectedVersionIds: DEFAULTS.staleRejectedIds,
    screenshots,
    blockers: screenshotReadiness.blockers,
    existingRejectionThread: {
      reviewSubmissionId: DEFAULTS.rejectedReviewSubmissionId,
      strategy: "new-submission-review-notes",
      reason: "No supported App Store Connect API reply endpoint was planned for the rejected review thread."
    },
    requests: [
      ...versionRequests(context),
      ...appInfoRequests(context),
      ...reviewDetailRequests(context),
      ...screenshotRequests(context, screenshots),
      ...submissionRequests(context, screenshotReadiness.ready)
    ]
  });
}

function versionRequests(context) {
  const { appId, platform, targetVersion, store, locale, releaseNotes, ids } = context;
  const versionAttributes = {
    description: store.description,
    keywords: store.keywords,
    locale,
    marketingUrl: store.marketingUrl,
    promotionalText: store.promotionalText,
    supportUrl: store.supportUrl,
    whatsNew: releaseNotes
  };
  const updateVersionAttributes = { ...versionAttributes };
  delete updateVersionAttributes.locale;

  return [
    {
      id: "fetch-target-app-store-version",
      method: "GET",
      path: `/v1/apps/${appId}/appStoreVersions`,
      query: { "filter[platform]": platform, "filter[versionString]": targetVersion, limit: "1" }
    },
    {
      id: "create-target-app-store-version",
      method: "POST",
      path: "/v1/appStoreVersions",
      body: {
        data: {
          type: "appStoreVersions",
          attributes: { platform, versionString: targetVersion, copyright: store.copyright },
          relationships: { app: relationship("apps", appId) }
        }
      }
    },
    {
      id: "fetch-version-localizations",
      method: "GET",
      path: `/v1/appStoreVersions/${ids.targetVersionId}/appStoreVersionLocalizations`,
      query: { limit: "200" }
    },
    {
      id: "create-version-localization",
      method: "POST",
      path: "/v1/appStoreVersionLocalizations",
      body: {
        data: {
          type: "appStoreVersionLocalizations",
          attributes: versionAttributes,
          relationships: { appStoreVersion: relationship("appStoreVersions", ids.targetVersionId) }
        }
      }
    },
    {
      id: "update-version-localization",
      method: "PATCH",
      path: `/v1/appStoreVersionLocalizations/${ids.appStoreVersionLocalizationId}`,
      body: {
        data: {
          type: "appStoreVersionLocalizations",
          id: ids.appStoreVersionLocalizationId,
          attributes: updateVersionAttributes
        }
      }
    }
  ];
}

function appInfoRequests(context) {
  const { appId, store, ids } = context;
  return [
    {
      id: "fetch-app-infos",
      method: "GET",
      path: `/v1/apps/${appId}/appInfos`,
      query: { include: "appInfoLocalizations,primaryCategory", limit: "200" }
    },
    {
      id: "fetch-app-info-localizations",
      method: "GET",
      path: `/v1/appInfos/${ids.appInfoId}/appInfoLocalizations`,
      query: { limit: "200" }
    },
    {
      id: "create-app-info-localization",
      method: "POST",
      path: "/v1/appInfoLocalizations",
      body: {
        data: {
          type: "appInfoLocalizations",
          attributes: {
            locale: context.locale,
            name: "Ouro MD",
            subtitle: store.subtitle,
            privacyPolicyUrl: store.privacy?.policyUrl
          },
          relationships: { appInfo: relationship("appInfos", ids.appInfoId) }
        }
      }
    },
    {
      id: "update-app-info-localization",
      method: "PATCH",
      path: `/v1/appInfoLocalizations/${ids.appInfoLocalizationId}`,
      body: {
        data: {
          type: "appInfoLocalizations",
          id: ids.appInfoLocalizationId,
          attributes: {
            name: "Ouro MD",
            subtitle: store.subtitle,
            privacyPolicyUrl: store.privacy?.policyUrl
          }
        }
      }
    },
    {
      id: "update-app-category",
      method: "PATCH",
      path: `/v1/appInfos/${ids.appInfoId}`,
      body: {
        data: {
          type: "appInfos",
          id: ids.appInfoId,
          relationships: { primaryCategory: relationship("appCategories", store.category) }
        }
      }
    }
  ];
}

function reviewDetailRequests(context) {
  const { store, ids } = context;
  return [
    {
      id: "fetch-app-review-detail",
      method: "GET",
      path: `/v1/appStoreVersions/${ids.targetVersionId}/appStoreReviewDetail`
    },
    {
      id: "update-app-review-detail",
      method: "PATCH",
      path: `/v1/appStoreReviewDetails/${ids.appStoreReviewDetailId}`,
      body: {
        data: {
          type: "appStoreReviewDetails",
          id: ids.appStoreReviewDetailId,
          attributes: { notes: store.reviewNotes }
        }
      }
    }
  ];
}

function screenshotRequests(context, screenshots) {
  const { ids } = context;
  const requests = [
    {
      id: "fetch-desktop-screenshot-set",
      method: "GET",
      path: `/v1/appStoreVersionLocalizations/${ids.appStoreVersionLocalizationId}/appScreenshotSets`,
      query: { limit: "200" }
    },
    {
      id: "create-desktop-screenshot-set",
      method: "POST",
      path: "/v1/appScreenshotSets",
      body: {
        data: {
          type: "appScreenshotSets",
          attributes: { screenshotDisplayType: "APP_DESKTOP" },
          relationships: {
            appStoreVersionLocalization: relationship("appStoreVersionLocalizations", ids.appStoreVersionLocalizationId)
          }
        }
      }
    }
  ];

  screenshots.forEach((screenshot, index) => {
    const ordinal = String(index + 1).padStart(2, "0");
    const baseId = `${ordinal}-${screenshot.scene}`;
    requests.push({
      id: `reserve-screenshot-${baseId}`,
      method: "POST",
      path: "/v1/appScreenshots",
      body: {
        data: {
          type: "appScreenshots",
          attributes: { fileSize: screenshot.fileSize, fileName: screenshot.fileName },
          relationships: { appScreenshotSet: relationship("appScreenshotSets", ids.appScreenshotSetId) }
        }
      }
    });
    requests.push({
      id: `upload-screenshot-${baseId}`,
      method: "UPLOAD_OPERATIONS",
      dependsOn: `reserve-screenshot-${baseId}`,
      uploadOperationsSource: "response.data.attributes.uploadOperations",
      filePath: screenshot.path,
      fileSize: screenshot.fileSize,
      sourceFileChecksum: screenshot.sourceFileChecksum
    });
    requests.push({
      id: `commit-screenshot-${baseId}`,
      method: "PATCH",
      path: `/v1/appScreenshots/\${appScreenshotId:${baseId}}`,
      body: {
        data: {
          type: "appScreenshots",
          id: `\${appScreenshotId:${baseId}}`,
          attributes: {
            sourceFileChecksum: screenshot.sourceFileChecksum,
            uploaded: true
          }
        }
      }
    });
  });

  return requests;
}

function submissionRequests(context, includeSubmit) {
  const { appId, platform, ids } = context;
  const requests = [
    {
      id: "associate-processed-build",
      method: "PATCH",
      path: `/v1/appStoreVersions/${ids.targetVersionId}/relationships/build`,
      body: { data: { type: "builds", id: ids.processedBuildId } }
    },
    {
      id: "create-review-submission",
      method: "POST",
      path: "/v1/reviewSubmissions",
      body: {
        data: {
          type: "reviewSubmissions",
          attributes: { platform },
          relationships: { app: relationship("apps", appId) }
        }
      }
    }
  ];
  if (!includeSubmit) return requests;
  return [
    ...requests,
    {
      id: "create-review-submission-item",
      method: "POST",
      path: "/v1/reviewSubmissionItems",
      body: {
        data: {
          type: "reviewSubmissionItems",
          relationships: {
            reviewSubmission: relationship("reviewSubmissions", ids.reviewSubmissionId),
            appStoreVersion: relationship("appStoreVersions", ids.targetVersionId)
          }
        }
      }
    },
    {
      id: "submit-review-submission",
      method: "PATCH",
      path: `/v1/reviewSubmissions/${ids.reviewSubmissionId}`,
      body: {
        data: {
          type: "reviewSubmissions",
          id: ids.reviewSubmissionId,
          attributes: { submitted: true }
        }
      }
    }
  ];
}

function validateScreenshotReadiness(screenshots, requirements) {
  const minimumCount = Number.isInteger(requirements?.minimumCount) ? requirements.minimumCount : 4;
  const requiredScenes = Array.isArray(requirements?.requiredScenes) ? requirements.requiredScenes : [];
  const scenes = screenshots.map((screenshot) => screenshot.scene);
  const blockers = [];

  if (screenshots.length < minimumCount) {
    blockers.push({
      code: "local-screenshots-required-for-submit",
      message: `Final submit planning requires at least ${minimumCount} local screenshots.`,
      evidence: { screenshotCount: screenshots.length, minimumCount }
    });
  }

  const missingScenes = requiredScenes.filter((scene) => !scenes.includes(scene));
  if (missingScenes.length > 0) {
    blockers.push({
      code: "required-screenshot-scenes-missing",
      message: "Final submit planning requires local screenshots for every required scene.",
      evidence: { missingScenes }
    });
  }

  return { ready: blockers.length === 0, blockers };
}

function screenshotInputs(paths) {
  return paths
    .filter((path) => typeof path === "string" && path.trim() !== "" && !isRemoteStoreProof(path))
    .map((path, index) => {
      const bytes = fs.readFileSync(path);
      const scene = sceneFromFileName(path, index);
      return screenshotSummary(path, scene, bytes);
    });
}

function selftestScreenshots() {
  return [
    "folder-workspace",
    "command-palette",
    "search-outline",
    "themed-export-readability"
  ].map((scene, index) => {
    const ordinal = String(index + 1).padStart(2, "0");
    const fileName = `${ordinal}-${scene}.png`;
    return screenshotSummary(`store-assets/app-store/${fileName}`, scene, Buffer.from(`ouro-md-${scene}-app-store-screenshot-fixture`));
  });
}

function screenshotSummary(path, scene, bytes) {
  return {
    scene,
    path,
    fileName: basename(path),
    fileSize: bytes.length,
    sourceFileChecksum: createHash("md5").update(bytes).digest("hex")
  };
}

function sceneFromFileName(path, index) {
  const name = basename(path).replace(/\.[^.]+$/, "");
  const withoutOrdinal = name.replace(/^\d+[-_]/, "");
  return withoutOrdinal || `screenshot-${index + 1}`;
}

function requireAppStoreChannel(manifest, channelId) {
  const channel = Array.isArray(manifest.channels)
    ? manifest.channels.find((candidate) => candidate?.id === channelId)
    : undefined;
  if (!channel || channel.distribution !== "app-store" || !channel.store) {
    throw new Error(`App Store channel not found or incomplete: ${channelId}`);
  }
  if (channel.bundleId !== DEFAULTS.bundleId || manifest.app?.bundleId !== DEFAULTS.bundleId) {
    throw new Error(`unexpected bundle id in manifest: ${channel.bundleId ?? manifest.app?.bundleId}`);
  }
  return channel;
}

function readReleaseNotes(path) {
  const source = fs.readFileSync(path, "utf8");
  const block = source.match(/releaseHighlights\s*=\s*\[([\s\S]*?)\]/)?.[1] ?? "";
  const strings = [...block.matchAll(/"([^"]+)"/g)].map((match) => match[1]);
  if (strings.length === 0) throw new Error(`missing release highlights in ${path}`);
  return strings.join("\n");
}

function guardAgainstStaleTargetIds(options) {
  const targetIds = [
    options.targetVersionId,
    options.appStoreVersionLocalizationId,
    options.appStoreReviewDetailId,
    options.appScreenshotSetId,
    options.reviewSubmissionId
  ];
  const staleIds = targetIds.filter((id) => DEFAULTS.staleRejectedIds.includes(id));
  if (staleIds.length > 0) {
    throw new Error(`stale rejected App Store Connect id used for target graph: ${staleIds.join(",")}`);
  }
}

function relationship(type, id) {
  return { data: { type, id } };
}

function isRemoteStoreProof(asset) {
  try {
    const url = new URL(asset);
    return ["asc:", "appstoreconnect:", "app-store-connect:"].includes(url.protocol) && url.hostname !== "";
  } catch {
    return false;
  }
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

function writeOutput(plan, options) {
  const body = options.json ? `${JSON.stringify(plan, null, 2)}\n` : textSummary(plan);
  if (options.artifactPath) {
    fs.mkdirSync(dirname(options.artifactPath), { recursive: true });
    fs.writeFileSync(options.artifactPath, body);
  }
  process.stdout.write(body);
}

function textSummary(plan) {
  return [
    `Dry-run App Store request plan for ${plan.appId} ${plan.targetVersion} (${plan.platform})`,
    `Requests ${plan.requests.length}; screenshots ${plan.screenshots.length}`,
    `Review submission strategy: ${plan.existingRejectionThread.strategy}`
  ].join("\n") + "\n";
}

try {
  const options = parseArgs(process.argv.slice(2));
  writeOutput(buildPlan(options), options);
} catch (error) {
  process.stderr.write(`error: ${redactText(error instanceof Error ? error.message : String(error))}\n`);
  process.exit(1);
}
