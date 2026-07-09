#!/usr/bin/env node
import fs from "node:fs";

const REQUIRED_SCENES = [
  "folder-workspace",
  "command-palette",
  "search-outline",
  "themed-export-readability"
];

function validateStoreMetadata(manifest, options = {}) {
  const errors = [];
  const channel = Array.isArray(manifest.channels)
    ? manifest.channels.find((candidate) => candidate && candidate.id === "mac-app-store")
    : undefined;
  const store = channel && channel.store;
  const finalScreenshots = options.finalScreenshots === true;

  const fail = (message) => errors.push(message);
  const requireString = (field, limit) => {
    const value = store && store[field];
    if (typeof value !== "string" || value.trim() === "") {
      fail(`mac-app-store store.${field} is required`);
      return "";
    }
    if (limit && value.length > limit) {
      fail(`mac-app-store store.${field} exceeds ${limit} characters`);
    }
    return value;
  };

  if (!store) {
    fail("mac-app-store store metadata is required");
    return errors;
  }

  if (store.category !== "DEVELOPER_TOOLS") fail("mac-app-store category must be DEVELOPER_TOOLS");
  if (store.subtitle !== "Local Markdown Workspace") fail("mac-app-store subtitle must be Local Markdown Workspace");

  const promotionalText = requireString("promotionalText", 170);
  const description = requireString("description");
  const keywords = requireString("keywords", 100);
  const reviewNotes = requireString("reviewNotes");

  for (const forbidden of ["The Markdown App", "quiet Markdown editor"]) {
    for (const [field, value] of Object.entries({ promotionalText, description, reviewNotes })) {
      if (value.toLowerCase().includes(forbidden.toLowerCase())) {
        fail(`mac-app-store store.${field} must not use generic phrase: ${forbidden}`);
      }
    }
  }

  for (const required of ["local Markdown", "command palette"]) {
    if (!promotionalText.toLowerCase().includes(required.toLowerCase())) {
      fail(`mac-app-store promotionalText must mention ${required}`);
    }
  }
  for (const required of ["folder search", "PDF"]) {
    if (!description.toLowerCase().includes(required.toLowerCase())) {
      fail(`mac-app-store description must mention ${required}`);
    }
  }
  for (const required of ["markdown", "local files", "folder search", "outline", "command palette", "pdf"]) {
    if (!keywords.toLowerCase().includes(required.toLowerCase())) {
      fail(`mac-app-store keywords must include ${required}`);
    }
  }
  for (const required of ["Shift-Command-O", "File Tree", "Outline", "Search", "Command Palette", "PDF", "HTML", "No account"]) {
    if (!reviewNotes.toLowerCase().includes(required.toLowerCase())) {
      fail(`mac-app-store reviewNotes must include ${required}`);
    }
  }

  const screenshots = Array.isArray(store.screenshots) ? store.screenshots : [];
  if (screenshots.length === 0 || screenshots.some((asset) => typeof asset !== "string" || asset.trim() === "")) {
    fail("mac-app-store screenshots must include local assets or explicit remote proof");
  }

  const screenshotRequirements = store.screenshotRequirements;
  if (!screenshotRequirements || typeof screenshotRequirements !== "object" || Array.isArray(screenshotRequirements)) {
    fail("mac-app-store screenshotRequirements are required");
  } else {
    if (!Number.isInteger(screenshotRequirements.minimumCount) || screenshotRequirements.minimumCount < 4) {
      fail("mac-app-store screenshotRequirements.minimumCount must be at least 4");
    }
    const scenes = Array.isArray(screenshotRequirements.requiredScenes)
      ? screenshotRequirements.requiredScenes
      : [];
    for (const scene of REQUIRED_SCENES) {
      if (!scenes.includes(scene)) {
        fail(`mac-app-store screenshotRequirements.requiredScenes must include ${scene}`);
      }
    }
    if (finalScreenshots && screenshots.length < screenshotRequirements.minimumCount) {
      fail(`mac-app-store final screenshots must include at least ${screenshotRequirements.minimumCount} assets`);
    }
  }

  return errors;
}

function validManifest() {
  return {
    channels: [
      {
        id: "mac-app-store",
        store: {
          category: "DEVELOPER_TOOLS",
          subtitle: "Local Markdown Workspace",
          promotionalText: "Local Markdown workspace for Mac files: folder search, outline, command palette, themes, PDF/HTML export, no account.",
          description: "Ouro MD is a local Markdown workspace with folder search and PDF export.",
          keywords: "markdown,local files,folder search,outline,command palette,pdf,html export,gfm,mac",
          reviewNotes: "No account. Open a folder with Shift-Command-O, then use File Tree, Outline, Search, Command Palette, PDF, and HTML export.",
          screenshots: ["asc://screenshots/existing-proof"],
          screenshotRequirements: {
            minimumCount: 4,
            requiredScenes: REQUIRED_SCENES
          }
        }
      }
    ]
  };
}

function validFinalManifest() {
  const manifest = validManifest();
  manifest.channels[0].store.screenshots = [
    "store-assets/app-store/folder-workspace.png",
    "store-assets/app-store/command-palette.png",
    "store-assets/app-store/search-outline.png",
    "store-assets/app-store/themed-export-readability.png"
  ];
  return manifest;
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function runSelftest() {
  const cases = [
    ["valid draft metadata", validManifest(), false, true],
    ["valid final metadata", validFinalManifest(), true, true],
    ["missing mac app store channel", { channels: [] }, false, false],
    ["missing subtitle", (() => { const m = clone(validManifest()); delete m.channels[0].store.subtitle; return m; })(), false, false],
    ["wrong category", (() => { const m = clone(validManifest()); m.channels[0].store.category = "PRODUCTIVITY"; return m; })(), false, false],
    ["overlong promotional text", (() => { const m = clone(validManifest()); m.channels[0].store.promotionalText = "x".repeat(171); return m; })(), false, false],
    ["generic description", (() => { const m = clone(validManifest()); m.channels[0].store.description = "The Markdown App with folder search and PDF export."; return m; })(), false, false],
    ["missing promotional text value", (() => { const m = clone(validManifest()); m.channels[0].store.promotionalText = ""; return m; })(), false, false],
    ["missing description proof", (() => { const m = clone(validManifest()); m.channels[0].store.description = "Ouro MD is a local Markdown workspace."; return m; })(), false, false],
    ["missing keyword", (() => { const m = clone(validManifest()); m.channels[0].store.keywords = "markdown,pdf"; return m; })(), false, false],
    ["missing review step", (() => { const m = clone(validManifest()); m.channels[0].store.reviewNotes = "No account."; return m; })(), false, false],
    ["empty screenshots", (() => { const m = clone(validManifest()); m.channels[0].store.screenshots = []; return m; })(), false, false],
    ["blank screenshot proof", (() => { const m = clone(validManifest()); m.channels[0].store.screenshots = [""]; return m; })(), false, false],
    ["missing screenshot requirements", (() => { const m = clone(validManifest()); delete m.channels[0].store.screenshotRequirements; return m; })(), false, false],
    ["too-low screenshot requirement", (() => { const m = clone(validManifest()); m.channels[0].store.screenshotRequirements.minimumCount = 3; return m; })(), false, false],
    ["missing required screenshot scene", (() => { const m = clone(validManifest()); m.channels[0].store.screenshotRequirements.requiredScenes = ["folder-workspace", "command-palette", "search-outline"]; return m; })(), false, false],
    ["final screenshot count too low", validManifest(), true, false]
  ];

  let failed = 0;
  for (const [name, manifest, finalScreenshots, shouldPass] of cases) {
    const errors = validateStoreMetadata(manifest, { finalScreenshots });
    const passed = errors.length === 0;
    if (passed === shouldPass) {
      console.log(`ok: ${name}`);
    } else {
      failed += 1;
      console.error(`FAIL: ${name}`);
      console.error(errors.join("\n") || "expected failure but validation passed");
    }
  }
  return failed === 0 ? 0 : 1;
}

function parseArgs(argv) {
  const options = { manifestPath: "distribution/apple-distribution.json", finalScreenshots: false, selftest: false };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--selftest") options.selftest = true;
    else if (arg === "--final-screenshots") options.finalScreenshots = true;
    else if (arg === "--manifest") options.manifestPath = argv[++index];
    else throw new Error(`unknown argument: ${arg}`);
  }
  return options;
}

try {
  const options = parseArgs(process.argv.slice(2));
  if (options.selftest) process.exit(runSelftest());
  const manifest = JSON.parse(fs.readFileSync(options.manifestPath, "utf8"));
  const errors = validateStoreMetadata(manifest, { finalScreenshots: options.finalScreenshots });
  if (errors.length > 0) {
    for (const error of errors) console.error(`error: ${error}`);
    process.exit(1);
  }
  console.log("app store metadata contract ok");
} catch (error) {
  console.error(`error: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
}
