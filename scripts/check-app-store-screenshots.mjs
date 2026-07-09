#!/usr/bin/env node
import fs from "node:fs";

const REQUIRED_SCENES = [
  "folder-workspace",
  "command-palette",
  "search-outline",
  "themed-export-readability"
];
const MINIMUM_WIDTH = 1280;
const MINIMUM_HEIGHT = 800;

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
      return;
    }
    if (file.length < 1024) {
      errors.push(`screenshot ${index + 1} is unexpectedly small: ${asset}`);
    }
    const dimensions = pngDimensions(file);
    if (dimensions.width < MINIMUM_WIDTH || dimensions.height < MINIMUM_HEIGHT) {
      errors.push(
        `screenshot ${index + 1} is too small: ${asset} is ${dimensions.width}x${dimensions.height}; minimum is ${MINIMUM_WIDTH}x${MINIMUM_HEIGHT}`
      );
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

function pngDimensions(file) {
  return {
    width: file.readUInt32BE(16),
    height: file.readUInt32BE(20)
  };
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
  const tempDir = fs.mkdtempSync("/tmp/ouro-md-app-store-screenshot-check-");
  const remoteManifestPath = `${tempDir}/remote-proof-manifest.json`;
  const remoteManifest = {
    channels: [
      {
        id: "mac-app-store",
        store: {
          screenshots: ["asc://screenshots/remote-proof-only"]
        }
      }
    ]
  };
  fs.writeFileSync(remoteManifestPath, JSON.stringify(remoteManifest), "utf8");
  const errors = validateScreenshotAssets(remoteManifestPath);

  const tinyPngPath = `${tempDir}/01-folder-workspace.png`;
  fs.writeFileSync(tinyPngPath, tinyPNG());
  const tinyManifestPath = `${tempDir}/tiny-png-manifest.json`;
  fs.writeFileSync(tinyManifestPath, JSON.stringify({
    channels: [
      {
        id: "mac-app-store",
        store: {
          screenshots: [
            tinyPngPath,
            tinyPngPath.replace("01-folder-workspace", "02-command-palette"),
            tinyPngPath.replace("01-folder-workspace", "03-search-outline"),
            tinyPngPath.replace("01-folder-workspace", "04-themed-export-readability")
          ]
        }
      }
    ]
  }), "utf8");
  fs.copyFileSync(tinyPngPath, tinyPngPath.replace("01-folder-workspace", "02-command-palette"));
  fs.copyFileSync(tinyPngPath, tinyPngPath.replace("01-folder-workspace", "03-search-outline"));
  fs.copyFileSync(tinyPngPath, tinyPngPath.replace("01-folder-workspace", "04-themed-export-readability"));
  const tinyErrors = validateScreenshotAssets(tinyManifestPath);
  errors.push(...tinyErrors);
  fs.rmSync(tempDir, { recursive: true, force: true });
  if (
    !errors.some((error) => error.includes("local PNG"))
    || !errors.some((error) => error.includes("too small"))
  ) {
    console.error("expected selftest to cover remote-only and too-small PNG validation");
    return 1;
  }
  console.log(errors.join("\n"));
  return 0;
}

function tinyPNG() {
  return Buffer.from(
    "89504e470d0a1a0a0000000d4948445200000001000000010802000000907753de0000000c49444154789c6360000000020001e221bc330000000049454e44ae426082",
    "hex"
  );
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
