#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const outputPath = process.argv[2];
if (!outputPath) {
  console.error("usage: node scripts/generate-reading-performance-fixture.cjs OUTPUT.md");
  process.exit(2);
}

const target = {
  lines: 34105,
  blankLines: 2582,
  headings: 282,
  pipeLines: 9763,
  inlineLinks: 913,
  referenceDefinitions: 42,
  listBullets: 249,
  orderedList: 41,
  blockquote: 1,
  fenceLines: 2,
  maxLength: 1281,
  bucketCounts: {
    gt1000: 114,
    b750_1000: 218,
    b500_750: 433,
    b250_500: 1498,
    b100_250: 8887,
    b1_100: 20373
  }
};

const sectionCount = target.headings - 1;
const firstSectionsWithExtraBlank = target.blankLines - 1 - (sectionCount * 9);
const tableLinesPerSection = Array.from({ length: sectionCount }, (_, index) => 34 + (index < target.pipeLines - (sectionCount * 34) ? 1 : 0));
const proseLinesPerSection = Array.from({ length: sectionCount }, (_, index) => 75 + (index < 68 ? 1 : 0));
const mediumProsePerSection = Array.from({ length: sectionCount }, (_, index) => {
  if (index === 0) { return 15; }
  return index < 143 ? 14 : 13;
});

const bucketPlan = {
  table: {
    gt1000: 114,
    b750_1000: 218,
    b500_750: 433,
    b250_500: 1498,
    b100_250: 5000,
    b1_100: target.pipeLines - (114 + 218 + 433 + 1498 + 5000)
  },
  prose: {
    b100_250: 3796,
    b1_100: 21143 - 3796
  },
  bullets: {
    b100_250: 49,
    b1_100: target.listBullets - 49
  },
  headings: { b1_100: target.headings },
  ordered: { b1_100: target.orderedList },
  quote: { b1_100: target.blockquote },
  fence: { b1_100: target.fenceLines },
  refs: { b100_250: target.referenceDefinitions }
};

const bucketLengths = {
  gt1000: [1005, 1150],
  b750_1000: [760, 900],
  b500_750: [510, 650],
  b250_500: [260, 390],
  b100_250: [110, 190],
  b1_100: [12, 70]
};

function chooseLength(bucket, index, total) {
  const [min, max] = bucketLengths[bucket];
  if (total <= 1) { return bucket === "gt1000" ? target.maxLength : Math.floor((min + max) / 2); }
  if (bucket === "gt1000" && index === total - 1) { return target.maxLength; }
  const span = max - min;
  return min + Math.floor((span * index) / Math.max(1, total - 1));
}

function padLine(prefix, targetLength, filler) {
  if (prefix.length >= targetLength) {
    return prefix.slice(0, targetLength);
  }
  const fill = (filler + " ").repeat(Math.ceil((targetLength - prefix.length) / (filler.length + 1)));
  return (prefix + fill).slice(0, targetLength);
}

const state = {
  inlineLinksRemaining: target.inlineLinks,
  quoteUsed: false,
  fenceOpenUsed: false,
  fenceCloseUsed: false,
  lengthsUsed: {
    gt1000: 0, b750_1000: 0, b500_750: 0, b250_500: 0, b100_250: 0, b1_100: 0
  },
  lines: []
};

const bucketTotals = Object.fromEntries(
  Object.keys(target.bucketCounts).map((bucket) => [bucket, 0])
);
for (const plan of Object.values(bucketPlan)) {
  for (const [bucket, count] of Object.entries(plan)) {
    bucketTotals[bucket] += count;
  }
}

function nextLength(kind, preferredBucket) {
  const plan = bucketPlan[kind];
  const buckets = preferredBucket ? [preferredBucket, ...Object.keys(plan).filter((name) => name !== preferredBucket)] : Object.keys(plan);
  for (const bucket of buckets) {
    if ((plan[bucket] || 0) <= 0) { continue; }
    const used = state.lengthsUsed[bucket];
    plan[bucket] -= 1;
    state.lengthsUsed[bucket] += 1;
    return chooseLength(bucket, used, bucketTotals[bucket]);
  }
  throw new Error(`no remaining bucket for ${kind}`);
}

function addLine(line) {
  state.lines.push(line);
}

function addBlank() {
  addLine("");
}

function proseLine(section, index, medium) {
  const bucket = medium ? "b100_250" : "b1_100";
  const length = nextLength("prose", bucket);
  const wantsLink = state.inlineLinksRemaining > 0 && medium;
  const link = wantsLink ? `[ref ${state.inlineLinksRemaining}](https://example.test/reading/${section}/${index}) ` : "";
  if (wantsLink) { state.inlineLinksRemaining -= 1; }
  const prefix = `Section ${section} line ${index} ${link}`;
  return padLine(prefix, length, medium ? "bounded-render-workload" : "steady");
}

function tableLine(section, row) {
  const order = [
    "gt1000", "b750_1000", "b500_750", "b250_500", "b100_250", "b1_100"
  ].find((bucket) => (bucketPlan.table[bucket] || 0) > 0) || "b1_100";
  const length = nextLength("table", order);
  const prefix = `| s${String(section).padStart(3, "0")} | row ${String(row).padStart(3, "0")} | render | `;
  return padLine(prefix, Math.max(length - 2, prefix.length), "cell-data") + " |";
}

function bulletLine(section, index, ordered = false) {
  const kind = ordered ? "ordered" : "bullets";
  const bucket = ordered ? "b1_100" : ((bucketPlan.bullets.b100_250 || 0) > 0 ? "b100_250" : "b1_100");
  const length = nextLength(kind, bucket);
  const prefix = ordered
    ? `${index}. Ordered checkpoint for section ${section} `
    : `- Bullet checkpoint for section ${section} `;
  return padLine(prefix, length, ordered ? "sequence" : "note");
}

function headingLine(section) {
  const length = nextLength("headings", "b1_100");
  return padLine(`## Section ${section} synthetic reading guide `, length, "head");
}

function referenceLine(index) {
  const length = nextLength("refs", "b100_250");
  const prefix = `[synthetic-ref-${index}]: https://example.test/reference/${index} `;
  return padLine(prefix, length, "reference");
}

function maybeQuote(section) {
  if (state.quoteUsed) { return null; }
  state.quoteUsed = true;
  const length = nextLength("quote", "b1_100");
  return padLine(`> Quote marker for section ${section} `, length, "quote");
}

function maybeFence(opening) {
  const key = opening ? "fenceOpenUsed" : "fenceCloseUsed";
  if (state[key]) { return null; }
  state[key] = true;
  nextLength("fence", "b1_100");
  return "```";
}

addLine("# Synthetic Reading Performance Guide");
addBlank();

for (let section = 1; section <= sectionCount; section++) {
  addLine(headingLine(section));
  const blanksThisSection = 9 + (section <= firstSectionsWithExtraBlank ? 1 : 0);
  let blanksRemaining = blanksThisSection;

  addBlank(); blanksRemaining -= 1;

  const proseTotal = proseLinesPerSection[section - 1];
  const mediumTotal = mediumProsePerSection[section - 1];
  const shortTotal = proseTotal - mediumTotal;
  const quote = maybeQuote(section);
  if (quote) { addLine(quote); }
  addLine(proseLine(section, 1, true));
  addLine(proseLine(section, 2, false));
  addBlank(); blanksRemaining -= 1;

  const bullet = section <= target.listBullets ? bulletLine(section, section, false) : null;
  if (bullet) { addLine(bullet); }
  addLine(proseLine(section, 3, true));
  addBlank(); blanksRemaining -= 1;

  const ordered = section <= target.orderedList ? bulletLine(section, section, true) : null;
  if (ordered) { addLine(ordered); }
  addLine(proseLine(section, 4, false));
  addBlank(); blanksRemaining -= 1;

  if (section === 2) {
    const openFence = maybeFence(true);
    const closeFence = maybeFence(false);
    if (openFence) { addLine(openFence); }
    addLine(proseLine(section, 5, false));
    if (closeFence) { addLine(closeFence); }
  }

  for (let row = 1; row <= tableLinesPerSection[section - 1]; row++) {
    addLine(tableLine(section, row));
  }
  addBlank(); blanksRemaining -= 1;

  let shortUsed = 2 + (section === 2 ? 1 : 0);
  let mediumUsed = 2;
  const shortRemaining = shortTotal - shortUsed;
  const mediumRemaining = mediumTotal - mediumUsed;
  const groupSizes = [
    [Math.floor(mediumRemaining / 4), Math.floor(shortRemaining / 4)],
    [Math.floor(mediumRemaining / 4), Math.floor(shortRemaining / 4)],
    [Math.floor(mediumRemaining / 4), Math.floor(shortRemaining / 4)],
    [mediumRemaining - (Math.floor(mediumRemaining / 4) * 3), shortRemaining - (Math.floor(shortRemaining / 4) * 3)]
  ];
  let proseIndex = 6;
  for (const [mediumCount, shortCount] of groupSizes) {
    for (let i = 0; i < mediumCount; i++) {
      addLine(proseLine(section, proseIndex++, true));
    }
    for (let i = 0; i < shortCount; i++) {
      addLine(proseLine(section, proseIndex++, false));
    }
    if (blanksRemaining > 0) {
      addBlank();
      blanksRemaining -= 1;
    }
  }
  while (blanksRemaining > 0) {
    addBlank();
    blanksRemaining -= 1;
  }
}

for (let index = 1; index <= target.referenceDefinitions; index++) {
  addLine(referenceLine(index));
}

if (state.lines.length !== target.lines) {
  console.error(`generator bug: produced ${state.lines.length} lines, expected ${target.lines}`);
  process.exit(1);
}

const document = state.lines.join("\n") + "\n";
fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, document);

const lengths = state.lines.map((line) => line.length);
const metrics = {
  outputPath: path.resolve(outputPath),
  bytes: Buffer.byteLength(document, "utf8"),
  lines: state.lines.length,
  blankLines: state.lines.filter((line) => line === "").length,
  headings: state.lines.filter((line) => line.startsWith("#")).length,
  pipeLines: state.lines.filter((line) => line.includes("|")).length,
  inlineLinks: document.split("](").length - 1,
  referenceDefinitions: state.lines.filter((line) => /^\[synthetic-ref-\d+\]: /.test(line)).length,
  listBullets: state.lines.filter((line) => line.startsWith("- ")).length,
  orderedList: state.lines.filter((line) => /^\d+\. /.test(line)).length,
  blockquote: state.lines.filter((line) => line.startsWith(">")).length,
  fenceLines: state.lines.filter((line) => line === "```").length,
  maxLength: Math.max(...lengths),
  linesGt1000: lengths.filter((length) => length > 1000).length,
  lines750_1000: lengths.filter((length) => length > 750 && length <= 1000).length,
  lines500_750: lengths.filter((length) => length > 500 && length <= 750).length,
  lines250_500: lengths.filter((length) => length > 250 && length <= 500).length,
  lines100_250: lengths.filter((length) => length > 100 && length <= 250).length,
  lines1_100: lengths.filter((length) => length > 0 && length <= 100).length
};

console.log(JSON.stringify(metrics, null, 2));
