const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const { test } = require("node:test");
const modulePath = require("node:path").join(__dirname, "../Sources/OuroMD/web/large-document.js");

function api() {
  assert.ok(fs.existsSync(modulePath), "large-document compatibility implementation exists");
  const context = { window: {}, TextEncoder };
  vm.runInNewContext(fs.readFileSync(modulePath, "utf8"), context);
  return context.window.OuroLargeDocument;
}

test("UTF-8 threshold selects full Unicode documents without truncation", () => {
  const large = api();
  assert.equal(large.accepts("a".repeat(524287)), false);
  assert.equal(large.accepts("a".repeat(524288)), true);
  assert.equal(large.accepts("🙂".repeat(131072)), true);
  const original = "🙂 漢字\r\n".repeat(80000) + "END";
  assert.equal(large.buffer(original).value(), original);
});

test("textarea edits preserve untouched CRLF, Unicode, and final newline exactly", () => {
  const b = api().buffer("α\r\n🙂\r\nnear EOF\r\n");
  b.input("α\n🙂\nnear EOF!\n");
  assert.equal(b.value(), "α\r\n🙂\r\nnear EOF!\r\n");
  b.undo();
  assert.equal(b.value(), "α\r\n🙂\r\nnear EOF\r\n");
  b.redo();
  assert.equal(b.value(), "α\r\n🙂\r\nnear EOF!\r\n");
});

test("assistant edit, replace near EOF, undo and redo preserve the full source", () => {
  const original = "line 🙂\n".repeat(100000) + "LAST needle\n";
  const b = api().buffer(original);
  b.replace(original + "assistant\n");
  b.splice(original.indexOf("needle"), 6, "replacement");
  assert.equal(b.value(), original.replace("needle", "replacement") + "assistant\n");
  b.undo();
  assert.equal(b.value(), original + "assistant\n");
  b.undo();
  assert.equal(b.value(), original);
  b.redo();
  assert.equal(b.value(), original + "assistant\n");
});

test("external reload establishes a new undo baseline and lock rejects mutations", () => {
  const b = api().buffer("old");
  b.replace("local");
  b.load("external\r\n🙂");
  assert.equal(b.undo(), false);
  b.editable(false);
  assert.equal(b.replace("wrong"), false);
  assert.equal(b.input("wrong"), false);
  assert.equal(b.value(), "external\r\n🙂");
});

test("source offsets map textarea LF selections back to exact CRLF source", () => {
  const b = api().buffer("A\r\n🙂\r\nLAST");
  assert.equal(b.sourceOffset(5), 7);
  assert.equal(b.displayOffset(7), 5);
  b.splice(b.sourceOffset(5), 4, "END");
  assert.equal(b.value(), "A\r\n🙂\r\nEND");
});
