#!/usr/bin/env node
import fs from "node:fs";

const REQUIRED_SCENES = [
  "folder-workspace",
  "command-palette",
  "search-outline",
  "themed-export-readability"
];

function validateScreenshotAssets(manifestPath = "distribution/apple-distribution.json") {
  const errors = [];
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const channel = Array.isArray(manifest.channels)
    ? manifest.channels.find((candidate) => candidate?.id === "mac-app-store")
    : undefined;
  const store = channel?.store;
  const screenshots = Array.isArray(store?.screenshots) ? store.screenshots : [];

  if (!store) {
    errors.push("mac-app-store store metadata is required");
    return errors;
  }
  if (screenshots.length < REQUIRED_SCENES.length) {
    errors.push(`mac-app-store screenshots must include at least ${REQUIRED_SCENES.length} local PNG assets`);
  }

  REQUIRED_SCENES.forEach((scene, index) => {
    const asset = screenshots[index];
    if (typeof asset !== "string" || asset.trim() === "") {
      errors.push(`missing screenshot ${index + 1} for scene ${scene}`);
      return;
    }
    if (isRemoteStoreProof(asset)) {
      errors.push(`screenshot ${index + 1} for scene ${scene} must be a local PNG, not remote proof`);
      return;
    }
    if (!asset.includes(scene)) {
      errors.push(`screenshot ${index + 1} must be ordered scene ${scene}`);
    }
    if (!asset.endsWith(".png")) {
      errors.push(`screenshot ${index + 1} for scene ${scene} must be a PNG`);
      return;
    }
    if (!fs.existsSync(asset) || !fs.statSync(asset).isFile()) {
      errors.push(`screenshot ${index + 1} file does not exist: ${asset}`);
      return;
    }
    const file = fs.readFileSync(asset);
    if (!isPNG(file)) {
      errors.push(`screenshot ${index + 1} is not a PNG: ${asset}`);
    }
    if (file.length < 1024) {
      errors.push(`screenshot ${index + 1} is unexpectedly small: ${asset}`);
    }
  });

  return errors;
}

function isPNG(file) {
  return file.length >= 8
    && file[0] === 0x89
    && file[1] === 0x50
    && file[2] === 0x4e
    && file[3] === 0x47
    && file[4] === 0x0d
    && file[5] === 0x0a
    && file[6] === 0x1a
    && file[7] === 0x0a;
}

function isRemoteStoreProof(asset) {
  try {
    const url = new URL(asset);
    return ["asc:", "appstoreconnect:", "app-store-connect:"].includes(url.protocol) && url.hostname !== "";
  } catch {
    return false;
  }
}

function parseArgs(argv) {
  const options = { manifestPath: "distribution/apple-distribution.json", selftest: false };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--manifest") options.manifestPath = argv[++index];
    else if (arg === "--selftest") options.selftest = true;
    else throw new Error(`unknown argument: ${arg}`);
  }
  return options;
}

function runSelftest() {
  const errors = validateScreenshotAssets();
  if (errors.length === 0) {
    console.error("expected current manifest to fail until local screenshots exist");
    return 1;
  }
  console.log(errors.join("\n"));
  return 0;
}

try {
  const options = parseArgs(process.argv.slice(2));
  if (options.selftest) process.exit(runSelftest());
  const errors = validateScreenshotAssets(options.manifestPath);
  if (errors.length > 0) {
    for (const error of errors) console.error(`error: ${error}`);
    process.exit(1);
  }
  console.log("app store screenshot assets ok");
} catch (error) {
  console.error(`error: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
}
