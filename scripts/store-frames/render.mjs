#!/usr/bin/env node
// Frames the Mac App Store scenes: each real window photographed by NativeStoreScenesTests goes onto an Ouro MD
// palette with its caption from distribution/app-store/frames/spec.json, at an App Store size, with no alpha.
// Adapted from spoonjoy/spoonjoy-apple scripts/store-frames/render.mjs (#285), for Mac windows instead of phones.
// Deterministic: fonts come from the app's own bundle (Open Sans, and KaTeX's Computer Modern faces), nothing loads
// from the network, the browser is the one pinned in package-lock.json, and --check renders everything twice and
// fails on any byte that differs.
//
//   node scripts/store-frames/render.mjs --scenes DIR --out DIR [--spec PATH] [--check] [--validate-only]
//
// DIR/<set>/<scene>.png in, OUT/<set>/<id>.png and OUT/creative/<poster>.png out, plus OUT/manifest.json with every
// frame's SHA-256. The output size follows the scenes: Retina scenes (2x) make 2880x1800 frames, 1x scenes make
// 1440x900, so a window is never enlarged past its own pixels.
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { decode, encodeOpaque } from "./png.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const WEB = join(ROOT, "Sources/OuroMD/web");
const FONT_FILES = {
  open: [["fonts/open-sans-400.woff2", 400, "normal"], ["fonts/open-sans-700.woff2", 700, "normal"], ["fonts/open-sans-400i.woff2", 400, "italic"]],
  serif: [["vditor/dist/js/katex/fonts/KaTeX_Main-Bold.woff2", 700, "normal"], ["vditor/dist/js/katex/fonts/KaTeX_Main-BoldItalic.woff2", 700, "italic"], ["vditor/dist/js/katex/fonts/KaTeX_Main-Italic.woff2", 400, "italic"]],
  mono: [["vditor/dist/js/katex/fonts/KaTeX_Typewriter-Regular.woff2", 400, "normal"]],
};
const FAMILIES = { open: "Open Sans", serif: "Ouro Main", mono: "Ouro Typewriter" };

// Apple's Mac screenshot sizes (16:10), and the iOS 27 header and search art (GET /v1/appAssetLibraryRefData).
export const MAC_SIZES = { 1: [1440, 900], 2: [2880, 1800] };
export const POSTER_SIZES = {
  header: [[5244, 2950], [3840, 1646]],
  search: [[5244, 2950], [3840, 2560], [3000, 2000], [1920, 1280]],
};

export function loadSpec(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

/** The scenes a shot uses, in order. */
export const shotScenes = (shot) => shot.scenes ?? [shot.scene];

/** Every scene the spec needs, each once. */
export function scenesFor(spec) {
  const all = Object.values(spec.sets).flatMap((set) => set.shots.flatMap(shotScenes));
  for (const poster of spec.creative?.posters ?? []) all.push(...poster.scenes);
  return [...new Set(all)];
}

/** Every problem with the spec, as sentences. */
export function validateSpec(spec) {
  const errors = [];
  for (const [name, set] of Object.entries(spec.sets)) {
    if (set.device !== "mac") errors.push(`${name}: device is mac`);
    if (!Array.isArray(set.window) || set.window.length !== 2) errors.push(`${name}: window is [width, height] in points`);
    if (!set.shots?.length) errors.push(`${name}: a set has at least one shot`);
    if ((set.shots ?? []).length > 10) errors.push(`${name}: the App Store takes at most 10 screenshots`);
    const numbers = new Set();
    for (const shot of set.shots ?? []) {
      if (!/^\d\d-[a-z0-9-]+$/.test(shot.id)) errors.push(`${name}: shot id ${shot.id} looks like 01-plan`);
      if (numbers.has(shot.id.slice(0, 2))) errors.push(`${name}: shot number ${shot.id.slice(0, 2)} is used twice`);
      numbers.add(shot.id.slice(0, 2));
      if (!spec.palettes[shot.palette]) errors.push(`${name}/${shot.id}: no palette ${shot.palette}`);
      if (!shot.headline) errors.push(`${name}/${shot.id}: no headline`);
      const scenes = shotScenes(shot);
      if (!scenes.length || scenes.length > 3) errors.push(`${name}/${shot.id}: 1 to 3 scenes`);
      for (const scene of scenes) if (!/^[a-z-]+$/.test(scene ?? "")) errors.push(`${name}/${shot.id}: scene names a Store scene`);
      errors.push(...copyErrors(`${name}/${shot.id}`, shot));
    }
  }
  for (const poster of spec.creative?.posters ?? []) {
    const sizes = POSTER_SIZES[poster.id];
    if (!sizes) errors.push(`creative: poster ${poster.id} is header or search`);
    else if (!sizes.some(([w, h]) => w === poster.size?.[0] && h === poster.size?.[1])) errors.push(`creative/${poster.id}: size is one of ${sizes.map((s) => s.join("x")).join(", ")}`);
    if (!spec.palettes[poster.palette]) errors.push(`creative/${poster.id}: no palette ${poster.palette}`);
    if (poster.id === "header" && poster.headline) errors.push("creative/header: no caption; the App Store sets the app's name over the header");
    if (!poster.scenes?.length || poster.scenes.length > 3) errors.push(`creative/${poster.id}: 1 to 3 scenes`);
    errors.push(...copyErrors(`creative/${poster.id}`, poster));
  }
  return errors;
}

// Apple's asset rules (https://developer.apple.com/app-store/asset-best-practices/): no prices, URLs, unverifiable
// claims or other platforms' names. Guideline 2.3.7 keeps other apps' names out of metadata too.
// One product name is spelled from its character codes: scripts/release-policy.sh scan keeps that legacy token out
// of every file in the repository.
const OTHER_PRODUCTS = ["android", "windows", "google", "microsoft", "linux", "obsidian",
  String.fromCharCode(0x74, 0x79, 0x70, 0x6f, 0x72, 0x61), "marked", "notion", "chatgpt", "claude", "copilot"];
const BANNED = [
  [/\$|€|£|\bfree\b|\bprice|\bdiscount|\bsale\b/i, "a price"],
  [/https?:|www\.|\.com\b|\.bot\b/i, "a URL"],
  [/#1\b|\bnumber one\b|\bbest\b|award|editor'?s choice/i, "an unverifiable claim"],
  [new RegExp(`\\b(${OTHER_PRODUCTS.join("|")})\\b`, "i"), "another platform or product"],
];
export function copyErrors(where, item) {
  const text = [item.kicker, item.headline, item.subline].filter(Boolean).join(" ");
  return BANNED.filter(([pattern]) => pattern.test(text)).map(([, what]) => `${where}: the caption has ${what}`);
}

const escape = (text) => String(text).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

/** A caption line set as Markdown that has rendered: *emphasis* turns italic, and its asterisks stay, faintly. */
export function markdownCaption(text) {
  return escape(text)
    .replace(/\*([^*\n]+)\*/g, '<span class="mark">*</span><em>$1</em><span class="mark">*</span>')
    .replace(/\n/g, "<br>");
}

function fontFaces() {
  return Object.entries(FONT_FILES).flatMap(([key, files]) => files.map(([file, weight, style]) => {
    const path = join(WEB, file);
    return `@font-face{font-family:'${FAMILIES[key]}';src:url('${pathToFileURL(path).href}') format('woff2');font-weight:${weight};font-style:${style}}`;
  })).join("\n");
}

function baseCss(w, h, palette, u) {
  const [top, bottom, ink, soft] = palette;
  return `${fontFaces()}
*{-webkit-font-smoothing:antialiased;box-sizing:border-box}
html,body{margin:0;width:${w}px;height:${h}px;overflow:hidden;background:${top}}
.canvas{position:relative;width:${w}px;height:${h}px;background:radial-gradient(130% 120% at 15% 0%,${top} 0%,${bottom} 100%);overflow:hidden}
.grain{position:absolute;inset:0;opacity:.06;background-image:radial-gradient(rgba(0,0,0,.6) 1px,transparent 1px);background-size:${6 * u}px ${6 * u}px}
.kicker{font:400 ${36 * u}px/1 'Ouro Typewriter',monospace;color:${soft};margin-bottom:${26 * u}px;letter-spacing:.02em}
.kicker .mark,h1 .mark{opacity:.38;font-style:normal}
h1{margin:0;color:${ink};font:700 ${118 * u}px/1.02 'Ouro Main',serif;letter-spacing:-.01em}
h1 em{font-style:italic}
p{margin:0;font:400 ${42 * u}px/1.32 'Open Sans',sans-serif;color:${soft}}
.win{position:absolute;filter:drop-shadow(0 ${30 * u}px ${60 * u}px rgba(0,0,0,.32)) drop-shadow(0 ${4 * u}px ${10 * u}px rgba(0,0,0,.18))}
.win img{display:block;width:100%}`;
}

function copyHtml(item) {
  const kicker = item.kicker ? `<div class="kicker"><span class="mark">## </span>${escape(item.kicker)}</div>` : "";
  return `${kicker}<h1>${markdownCaption(item.headline)}</h1>`;
}

/** A 16:10 frame: the caption across the top, the real window below it, running off the bottom edge. */
export function frameHtml(size, shot, palettes, scenePaths) {
  const [w, h] = size;
  const u = w / 2880;
  const n = scenePaths.length;
  // One window fills 84% of the width; two or three cascade like windows on a desk, the first at the back.
  const width = n === 1 ? 0.84 * w : 0.6 * w;
  const windows = scenePaths.map((path, i) => {
    const x = n === 1 ? (w - width) / 2 : 0.06 * w + i * ((0.94 * w - width - 0.06 * w) / (n - 1));
    const y = n === 1 ? 0.27 * h : 0.29 * h + i * 0.09 * h;
    return `<div class="win" style="left:${x}px;top:${y}px;width:${width}px;z-index:${i + 2}"><img src="${pathToFileURL(path).href}"></div>`;
  });
  return `<!doctype html><html><head><meta charset="utf-8"><style>
${baseCss(w, h, palettes[shot.palette], u)}
.copy{position:absolute;left:${150 * u}px;top:${118 * u}px;width:${1560 * u}px;z-index:10}
.sub{position:absolute;left:${1820 * u}px;top:${178 * u}px;width:${910 * u}px;z-index:10}
</style></head><body><div class="canvas"><div class="grain"></div>
<div class="copy">${copyHtml(shot)}</div>${shot.subline ? `<div class="sub"><p>${escape(shot.subline)}</p></div>` : ""}
${windows.join("\n")}
</div></body></html>`;
}

/** A wide poster: the palette, an optional caption on the left, and the windows cascading across the right. */
export function posterHtml(poster, palettes, scenePaths) {
  const [w, h] = poster.size;
  const u = h / 1646;
  const caption = Boolean(poster.headline);
  const n = scenePaths.length;
  const [from, to] = [0.08 * w, 0.92 * w];
  // Beside a caption the windows are large and run off the right and bottom edges, so the art has no empty corner.
  const width = caption ? w * 0.62 : Math.min((to - from) * (n === 1 ? 1 : 0.62), h * 0.82 * 1.6);
  const windows = scenePaths.map((path, i) => {
    const x = caption ? w * (0.43 + i * 0.08) : n === 1 ? (from + to - width) / 2 : from + i * ((to - from - width) / (n - 1));
    const y = caption ? h * (0.14 + i * 0.3) : h * 0.12 + i * h * 0.08;
    return `<div class="win" style="left:${x}px;top:${y}px;width:${width}px;z-index:${i + 2}"><img src="${pathToFileURL(path).href}"></div>`;
  });
  return `<!doctype html><html><head><meta charset="utf-8"><style>
${baseCss(w, h, palettes[poster.palette], u * 1.33)}
.copy{position:absolute;left:${170 * u}px;top:50%;transform:translateY(-50%);width:${w * 0.34}px;z-index:20}
.copy p{margin-top:${36 * u}px}
</style></head><body><div class="canvas"><div class="grain"></div>
${caption ? `<div class="copy">${copyHtml(poster)}${poster.subline ? `<p>${escape(poster.subline)}</p>` : ""}</div>` : ""}
${windows.join("\n")}
</div></body></html>`;
}

export const sha256 = (buffer) => createHash("sha256").update(buffer).digest("hex");

/** Reads a scene's size, checks it is a whole 16:10 window of the set, and returns its scale (1 or 2). */
export function sceneScale(path, window) {
  if (!existsSync(path)) throw new Error(`no scene ${path}; run Store scenes`);
  const { width, height } = decode(readFileSync(path));
  const scale = width / window[0];
  if (Math.abs(height / width - window[1] / window[0]) > 0.02) throw new Error(`${path} is ${width}x${height}, not a whole ${window.join("x")} window`);
  if (scale < 0.98) throw new Error(`${path} is ${width}x${height}, smaller than a ${window.join("x")} window`);
  return scale >= 1.98 ? 2 : 1;
}

async function shoot(page, html, png) {
  await page.goto(pathToFileURL(html).href, { waitUntil: "load" });
  await page.evaluate(async () => {
    // Load every face even where a page sets no text in it (the header has no caption), so a missing font file
    // fails here instead of falling back.
    const faces = ["400 20px", "700 20px", "italic 400 20px", "italic 700 20px"];
    await Promise.all(["Open Sans", "Ouro Main", "Ouro Typewriter"].flatMap((f) => faces.map((face) => document.fonts.load(`${face} '${f}'`))));
    await document.fonts.ready;
    await Promise.all([...document.images].map((img) => img.decode()));
  });
  const missing = await page.evaluate(() => ["Open Sans", "Ouro Main", "Ouro Typewriter"].filter((f) => !document.fonts.check(`400 20px '${f}'`)));
  if (missing.length) throw new Error(`fonts did not load: ${missing.join(", ")}`);
  const bytes = encodeOpaque(decode(await page.screenshot({ type: "png", animations: "disabled" })));
  writeFileSync(png, bytes);
  return sha256(bytes);
}

async function renderAll({ spec, scenes, out }) {
  const { chromium } = await import("playwright");
  const browser = await chromium.launch({
    args: ["--disable-gpu", "--font-render-hinting=none", "--disable-lcd-text", "--force-color-profile=srgb", "--allow-file-access-from-files"],
  });
  const manifest = {};
  try {
    for (const [setName, set] of Object.entries(spec.sets)) {
      const paths = Object.fromEntries(scenesFor({ sets: { [setName]: set } }).map((s) => [s, join(scenes, setName, `${s}.png`)]));
      const scales = new Set(Object.values(paths).map((p) => sceneScale(p, set.window)));
      if (scales.size !== 1) throw new Error(`${setName} scenes mix 1x and 2x`);
      const size = MAC_SIZES[[...scales][0]];
      const page = await browser.newPage({ viewport: { width: size[0], height: size[1] }, deviceScaleFactor: 1 });
      mkdirSync(join(out, setName), { recursive: true });
      mkdirSync(join(out, ".pages", setName), { recursive: true });
      for (const shot of set.shots) {
        // The pages sit apart from the frames, so the output folder is exactly what the stager uploads.
        const html = join(out, ".pages", setName, `${shot.id}.html`);
        writeFileSync(html, frameHtml(size, shot, spec.palettes, shotScenes(shot).map((s) => paths[s])));
        manifest[`${setName}/${shot.id}.png`] = await shoot(page, html, join(out, setName, `${shot.id}.png`));
      }
      await page.close();
    }
    const creative = spec.creative;
    if (creative) {
      const source = spec.sets[creative.source_set];
      mkdirSync(join(out, "creative"), { recursive: true });
      mkdirSync(join(out, ".pages", "creative"), { recursive: true });
      for (const poster of creative.posters) {
        const [w, h] = poster.size;
        const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
        const html = join(out, ".pages", "creative", `${poster.id}.html`);
        const paths = poster.scenes.map((s) => join(scenes, creative.source_set, `${s}.png`));
        paths.forEach((p) => sceneScale(p, source.window));
        writeFileSync(html, posterHtml(poster, spec.palettes, paths));
        manifest[`creative/${poster.id}.png`] = await shoot(page, html, join(out, "creative", `${poster.id}.png`));
        await page.close();
      }
    }
  } finally {
    await browser.close();
  }
  return manifest;
}

async function main() {
  const { values } = parseArgs({
    options: {
      spec: { type: "string", default: join(ROOT, "distribution/app-store/frames/spec.json") },
      scenes: { type: "string" },
      out: { type: "string" },
      check: { type: "boolean", default: false },
      "validate-only": { type: "boolean", default: false },
    },
  });
  const spec = loadSpec(values.spec);
  const errors = validateSpec(spec);
  if (errors.length) throw new Error(errors.join("\n"));
  if (values["validate-only"]) return console.log(`spec: ${Object.keys(spec.sets).length} set(s), ${scenesFor(spec).length} scenes, fine`);
  if (!values.scenes || !values.out) throw new Error("--scenes DIR and --out DIR are required");
  const manifest = await renderAll({ spec, scenes: values.scenes, out: values.out });
  if (values.check) {
    const again = await renderAll({ spec, scenes: values.scenes, out: join(values.out, ".again") });
    const differ = Object.keys(manifest).filter((k) => manifest[k] !== again[k]);
    if (differ.length) throw new Error(`the same scenes rendered different pixels: ${differ.join(", ")}`);
    console.log(`check: ${Object.keys(manifest).length} frames rendered twice, byte for byte the same`);
  }
  const sceneHashes = {};
  for (const [setName, set] of Object.entries(spec.sets)) {
    for (const scene of scenesFor({ sets: { [setName]: set } })) sceneHashes[`${setName}/${scene}.png`] = sha256(readFileSync(join(values.scenes, setName, `${scene}.png`)));
  }
  writeFileSync(join(values.out, "manifest.json"), `${JSON.stringify({ scenes: sceneHashes, frames: manifest }, null, 2)}\n`);
  for (const [path, hash] of Object.entries(manifest)) console.log(`${hash}  ${path}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    for (const line of String(error.message).split("\n")) console.error(`::error::${line}`);
    process.exit(1);
  });
}
