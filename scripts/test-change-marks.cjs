const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

const source = path.join(__dirname, "../Sources/OuroMD/web/change-marks.js");
const context = { window: {} };
if (fs.existsSync(source)) {
  vm.runInNewContext(fs.readFileSync(source, "utf8"), context);
}

function reconcile(before, after, external = true) {
  assert.equal(typeof context.window.OuroChangeMarks?.reconcile, "function", "passage reconciliation exists");
  return JSON.parse(JSON.stringify(context.window.OuroChangeMarks.reconcile(before, after, external)));
}

const rows = (values) => values.map((signature) => ({ signature, marked: false, deletion: false, seen: false }));
const marked = (values) => values.flatMap((value, index) => value.marked ? [index] : []);

test("independent external edits leave unchanged passages unmarked", () => {
  const result = reconcile(rows(["one", "two", "three", "four"]), ["ONE", "two", "THREE", "four"]);
  assert.deepEqual(marked(result), [0, 2]);
  assert.equal(result[1].signature, "two");
});

test("unchanged reload and empty input add no marks", () => {
  assert.deepEqual(marked(reconcile(rows(["same"]), ["same"])), []);
  assert.deepEqual(reconcile([], []), []);
  assert.deepEqual(marked(reconcile([], ["new"])), [0]);
});

test("repeated reloads preserve previous marks and reset changed passages", () => {
  const before = reconcile(rows(["one", "two", "three"]), ["ONE", "two", "three"]);
  before[0].seen = true;
  const after = reconcile(before, ["ONE", "two", "THREE"]);
  assert.deepEqual(marked(after), [0, 2]);
  assert.equal(after[0].seen, true);
  assert.equal(after[2].seen, false);
});

test("local edits reanchor earlier cues without marking ordinary typing", () => {
  const before = reconcile(rows(["one", "two"]), ["ONE", "two"]);
  const after = reconcile(before, ["intro", "ONE typed", "two"], false);
  assert.deepEqual(marked(after), [1]);
  assert.deepEqual(marked(reconcile(rows(["one"]), ["typed"], false)), []);
});

test("deletions mark their gap at the start, end and empty document", () => {
  const start = reconcile(rows(["one", "two"]), ["two"]);
  assert.equal(start[0].deletion, true);
  const end = reconcile(rows(["one", "two"]), ["one"]);
  assert.equal(end[0].deletion, true);
  const empty = reconcile(rows(["one"]), []);
  assert.equal(empty.length, 1);
  assert.equal(empty[0].deletion, true);
  assert.equal(empty[0].signature, "");
});

test("duplicate passages remain matched in order", () => {
  const after = reconcile(rows(["same", "old", "same", "tail"]), ["same", "new", "same", "tail"]);
  assert.deepEqual(marked(after), [1]);
});

test("large documents retain unchanged passages between distant edits", () => {
  const original = Array.from({ length: 2000 }, (_, i) => `passage ${i}`);
  const next = original.slice();
  next[2] = "first change";
  next[1997] = "last change";
  assert.deepEqual(marked(reconcile(rows(original), next)), [2, 1997]);
});

test("large diffs do not follow a moved first passage past unchanged content", () => {
  const original = Array.from({ length: 600 }, (_, i) => `passage ${i}`);
  const next = ["NEW", ...original.slice(1), original[0]];
  assert.deepEqual(marked(reconcile(rows(original), next)), [0, 600]);
});

test("only reached marks clear after scrolling past", () => {
  assert.equal(typeof context.window.OuroChangeMarks?.passed, "function", "scroll dismissal exists");
  const passed = context.window.OuroChangeMarks.passed;
  assert.equal(passed({ seen: false }, { top: -100, bottom: -60 }, 600), false);
  assert.equal(passed({ seen: true }, { top: -100, bottom: -60 }, 600), true);
  assert.equal(passed({ seen: true }, { top: 100, bottom: 140 }, 600), false);
  assert.equal(passed({ seen: true }, { top: 650, bottom: 700 }, 600), true);
  assert.equal(passed({ seen: true }, { top: -100, bottom: 700 }, 600), false);
});

test("a reached cue remains while visible at the native viewport top", () => {
  assert.equal(typeof context.window.OuroChangeMarks?.passed, "function");
  assert.equal(context.window.OuroChangeMarks.passed({ seen: true }, { top: 10, bottom: 30 }, 600), false);
});
