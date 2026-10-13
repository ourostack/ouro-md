const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

const bridge = fs.readFileSync(path.join(__dirname, "../Sources/OuroMD/web/bridge.js"), "utf8");
const match = bridge.match(/function setDirty\(d\) \{[\s\S]*?\n  \}/);

if (!match) {
  throw new Error("setDirty function not found in bridge.js");
}

test("repeated genuine local edits emit dirty true every time", () => {
  const posts = [];
  const context = {
    dirty: false,
    post: (type, payload) => posts.push({ type, payload }),
    result: null
  };
  vm.runInNewContext(`
${match[0]}
setDirty(true);
setDirty(true);
setDirty(false);
setDirty(false);
`, context);
  assert.equal(context.dirty, false);
  assert.deepEqual(JSON.parse(JSON.stringify(posts)), [
    { type: "dirty", payload: { dirty: true } },
    { type: "dirty", payload: { dirty: true } },
    { type: "dirty", payload: { dirty: false } }
  ]);
});
