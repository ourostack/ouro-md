import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { decode, encodeOpaque } from "../png.mjs";
import { frameHtml, loadSpec, markdownCaption, scenesFor, sha256, validateSpec } from "../render.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "../../..");
const SPEC = join(ROOT, "distribution/app-store/frames/spec.json");

function solid(width, height, rgba) {
  const pixels = Buffer.alloc(width * height * 4);
  for (let i = 0; i < width * height; i += 1) pixels.set(rgba, i * 4);
  return { width, height, channels: 4, pixels };
}

test("the checked-in spec is valid and names every scene the scene test takes", () => {
  const spec = loadSpec(SPEC);
  assert.deepEqual(validateSpec(spec), []);
  const swift = readFileSync(join(ROOT, "Tests/OuroMDTests/NativeStoreScenesTests.swift"), "utf8");
  for (const scene of scenesFor(spec)) {
    const named = swift.includes(`"${scene}"`) || (scene.startsWith("theme-") && swift.includes(`"${scene.slice(6)}"`));
    assert.ok(named, `NativeStoreScenesTests takes ${scene}`);
  }
  const listing = JSON.parse(readFileSync(join(ROOT, "distribution/app-store/listing.json"), "utf8"));
  assert.ok(listing.screenshots.mac.sizes.some(([w, h]) => w === 2880 && h === 1800));
  for (const field of ["price", "availability", "ageRating", "categories", "contentRightsDeclaration"]) {
    assert.equal(listing[field], undefined, `staging never sets ${field}`);
  }
});

test("captions with a price, a URL, a ranking or another product are refused", () => {
  const spec = loadSpec(SPEC);
  const shot = spec.sets.mac.shots[0];
  for (const [headline, what] of [["Free forever", "a price"], ["See ouroboros.bot", "a URL"], ["The #1 editor", "an unverifiable claim"], ["Better than Obsidian", "another platform"]]) {
    const bad = structuredClone(spec);
    bad.sets.mac.shots[0] = { ...shot, headline };
    assert.match(validateSpec(bad).join("\n"), new RegExp(what), headline);
  }
});

test("emphasis renders italic and keeps its asterisks, escaped", () => {
  assert.equal(markdownCaption("a *b* <c>\nd"), 'a <span class="mark">*</span><em>b</em><span class="mark">*</span> &lt;c&gt;<br>d');
});

test("frames load only the app's own fonts and nothing from the network", () => {
  const spec = loadSpec(SPEC);
  const html = frameHtml([1440, 900], spec.sets.mac.shots[0], spec.palettes, ["/tmp/s.png"]);
  assert.match(html, /Sources\/OuroMD\/web\/fonts\/open-sans-400\.woff2/);
  assert.match(html, /KaTeX_Main-Bold\.woff2/);
  assert.doesNotMatch(html, /https?:\/\//);
});

test("1x scenes make the same 1440x900 frames twice, without alpha", { timeout: 180000 }, () => {
  const dir = mkdtempSync(join(tmpdir(), "store-frames-"));
  const spec = loadSpec(SPEC);
  spec.sets.mac.shots = spec.sets.mac.shots.slice(0, 1);
  delete spec.creative;
  writeFileSync(join(dir, "spec.json"), JSON.stringify(spec));
  mkdirSync(join(dir, "scenes/mac"), { recursive: true });
  writeFileSync(join(dir, "scenes/mac/plan-page.png"), encodeOpaque(solid(1440, 900, [250, 250, 250, 255])));
  const out = execFileSync(process.execPath, [join(HERE, "../render.mjs"), "--spec", join(dir, "spec.json"), "--scenes", join(dir, "scenes"), "--out", join(dir, "out"), "--check"], { encoding: "utf8" });
  assert.match(out, /rendered twice, byte for byte the same/);
  const png = readFileSync(join(dir, "out/mac/01-plan.png"));
  const image = decode(png);
  assert.deepEqual([image.width, image.height, image.channels], [1440, 900, 3]);
  assert.equal(JSON.parse(readFileSync(join(dir, "out/manifest.json"), "utf8")).frames["mac/01-plan.png"], sha256(png));
});

test("a clipped window is refused", () => {
  const dir = mkdtempSync(join(tmpdir(), "store-frames-"));
  const spec = loadSpec(SPEC);
  delete spec.creative;
  writeFileSync(join(dir, "spec.json"), JSON.stringify(spec));
  mkdirSync(join(dir, "scenes/mac"), { recursive: true });
  for (const scene of scenesFor(spec)) writeFileSync(join(dir, `scenes/mac/${scene}.png`), encodeOpaque(solid(1024, 768, [250, 250, 250, 255])));
  assert.throws(() => execFileSync(process.execPath, [join(HERE, "../render.mjs"), "--spec", join(dir, "spec.json"), "--scenes", join(dir, "scenes"), "--out", join(dir, "out")], { encoding: "utf8", stdio: "pipe" }), /not a whole 1440x900 window/);
});
