"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const cp = require("node:child_process");
const { preprocess } = require("./index.js");

function setup(t, failCommand) {
  const inputDir = fs.mkdtempSync(path.join(os.tmpdir(), "ditaa-test-"));
  t.after(() => fs.rmSync(inputDir, { recursive: true, force: true }));
  const calls = [];
  t.mock.method(cp, "spawnSync", (command, args) => {
    calls.push({ command, args });
    if (command === "ditaa") {
      assert.match(fs.readFileSync(args.at(-2), "utf8"), /Source/);
      fs.writeFileSync(args.at(-1), "rendered PNG");
    }
    return command === failCommand
      ? { status: 1, stderr: "test failure" }
      : { status: 0 };
  });
  return { inputDir, calls };
}

function diagram(options = "") {
  return `\`\`\`ditaa${options}\n+--------+\n| Source |\n+--------+\n\`\`\`\n`;
}

for (const [options, transparent, invert] of [
  ["", false, false],
  [" [transparent]", true, false],
  [" [invert]", false, true],
  [" [transparent invert w:600]", true, true],
]) {
  test(`renders ditaa ${options || "without options"}`, t => {
    const context = setup(t);
    const result = preprocess(diagram(options), context);
    assert.match(result, /^!\[(?:w:600)?\]\(\.imggen\/ditaa-[a-f0-9]{64}\.png\)\n$/);
    const [render, inversion] = context.calls;
    assert.equal(render.command, "ditaa");
    assert.equal(render.args.includes("--transparent"), transparent);
    assert.equal(render.args.includes("--no-shadows"), transparent);
    assert.deepEqual(render.args.slice(0, 2), ["--encoding", "UTF-8"]);
    assert.equal(context.calls.length, invert ? 2 : 1);
    if (invert) {
      assert.equal(inversion.command, "magick");
      assert.deepEqual(inversion.args.slice(1, -1), ["-channel", "RGB", "-negate", "+channel"]);
      assert.equal(inversion.args[0], inversion.args.at(-1));
    }
    const files = fs.readdirSync(path.join(context.inputDir, ".imggen"));
    assert.equal(files.length, 1, "only the completed PNG remains");
    assert.match(files[0], /\.png$/);
  });
}

test("cache varies by rendering flags but not their order or Marp sizing", t => {
  const context = setup(t);
  const results = ["", " [transparent]", " [invert]", " [transparent invert]"]
    .map(options => preprocess(diagram(options), context));
  assert.equal(new Set(results).size, 4);
  assert.equal(context.calls.length, 6);
  const cached = preprocess(diagram(" [invert transparent w:600]"), context);
  assert.equal(cached.replace("w:600", ""), results[3]);
  assert.equal(context.calls.length, 6, "cached combined render is reused");
});

for (const command of ["ditaa", "magick"]) {
  test(`${command} failure preserves source and does not cache partial PNG`, t => {
    const context = setup(t, command);
    const markdown = diagram(" [transparent invert]");
    assert.equal(preprocess(markdown, context), markdown);
    assert.deepEqual(fs.readdirSync(path.join(context.inputDir, ".imggen")), []);
    preprocess(markdown, context);
    assert.equal(context.calls.filter(call => call.command === "ditaa").length, 2);
  });
}

test("a missing executable preserves source and cleans up", t => {
  const context = setup(t);
  t.mock.method(cp, "spawnSync", () => ({ status: null, error: new Error("ENOENT") }));
  const markdown = diagram(" [invert]");
  assert.equal(preprocess(markdown, context), markdown);
  assert.deepEqual(fs.readdirSync(path.join(context.inputDir, ".imggen")), []);
});

test("supports CRLF and comma-separated flags, without matching option substrings", t => {
  const context = setup(t);
  assert.match(preprocess(diagram("[transparent,invert]").replace(/\n/g, "\r\n"), context), /^!\[\]/);
  assert.equal(context.calls.length, 2);
  preprocess(diagram(" [not-transparent not-invert]"), context);
  assert.equal(context.calls.length, 3);
  assert.equal(context.calls[2].args.includes("--transparent"), false);
});

test("leaves other markdown untouched", t => {
  const context = setup(t);
  const markdown = "# Slide\n```text\nSource\n```\n";
  assert.equal(preprocess(markdown, context), markdown);
  assert.equal(context.calls.length, 0);
});
