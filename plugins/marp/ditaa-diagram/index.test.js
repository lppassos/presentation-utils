"use strict";

// Run: node --test plugins/marp/ditaa-diagram/index.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const crypto = require("node:crypto");
const cp = require("node:child_process");
const { preprocess, conversionNeeded, convertToImg } = require("./index.js");

const content = "+-----+\n| Box |\n+-----+\n";
const fence = (source = content) => `\`\`\`ditaa\n${source}\`\`\`\n`;
const imagePath = (source) =>
  `.imggen/ditaa-${crypto.createHash("sha256").update(source).digest("hex")}.png`;

function setup(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ditaa-diagram-test-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function renderer(t, fn) {
  return t.mock.method(cp, "spawnSync", fn || ((_cmd, args) => {
    fs.writeFileSync(args[args.length - 1], "PNG");
    return { status: 0 };
  }));
}

test("unrelated Markdown and other diagram blocks are unchanged", (t) => {
  const dir = setup(t);
  const spawn = renderer(t);
  const md = "# Slide\n```mermaid\ngraph TD\n```\n```ditaax\ntext\n```\n";
  assert.equal(preprocess(md, { inputDir: dir }), md);
  assert.equal(spawn.mock.callCount(), 0);
});

test("renders using UTF-8 CLI arguments, cleans source, and produces an image", (t) => {
  const dir = setup(t);
  const spawn = renderer(t);
  const png = path.join(dir, imagePath(content));
  assert.equal(conversionNeeded(png), true);
  assert.equal(preprocess(fence(), { inputDir: dir }), `![](${imagePath(content)})\n`);
  assert.equal(conversionNeeded(png), false);
  const { arguments: [cmd, args, options] } = spawn.mock.calls[0];
  assert.equal(cmd, "java");
  assert.deepEqual(args.slice(0, 6), ["-Djava.awt.headless=true", "-jar", "/usr/bin/ditaa", "--overwrite", "--encoding", "UTF-8"]);
  assert.equal(fs.existsSync(path.dirname(args[6])), false);
  assert.equal(options.encoding, "utf8");
  assert.equal(fs.existsSync(args[6]), false);
});

test("preserves Marp image options and CRLF input", (t) => {
  const dir = setup(t);
  renderer(t);
  const source = content.replace(/\n/g, "\r\n");
  const md = `\`\`\`ditaa [width:600px height:200px]\r\n${source}\`\`\`\r\n`;
  assert.equal(preprocess(md, { inputDir: dir }), `![width:600px height:200px](${imagePath(source)})\r\n`);
});

test("identical blocks and later calls use cached PNGs; changed content renders separately", (t) => {
  const dir = setup(t);
  const spawn = renderer(t);
  const second = content.replace("Box", "Two");
  const md = fence() + fence() + fence(second);
  const expected = `![](${imagePath(content)})\n![](${imagePath(content)})\n![](${imagePath(second)})\n`;
  assert.equal(preprocess(md, { inputDir: dir }), expected);
  assert.equal(spawn.mock.callCount(), 2);
  assert.equal(preprocess(md, { inputDir: dir }), expected);
  assert.equal(spawn.mock.callCount(), 2);
});

for (const failure of ["exit", "missing executable", "missing output", "throw"]) {
  test(`failed render (${failure}) retains fence, warns, and removes temporary/partial files`, (t) => {
    const dir = setup(t);
    renderer(t, (_cmd, args) => {
      assert.equal(fs.readFileSync(args[6], "utf8"), content);
      if (failure === "missing output") return { status: 0 };
      fs.writeFileSync(args[7], "partial PNG");
      if (failure === "throw") throw new Error("spawn failed");
      if (failure === "missing executable") return { status: null, error: new Error("ENOENT") };
      return { status: 1, stderr: "bad diagram" };
    });
    const warnings = [];
    t.mock.method(process.stderr, "write", (text) => { warnings.push(text); return true; });
    assert.equal(preprocess(fence(), { inputDir: dir }), fence());
    assert.match(warnings.join(""), /\[ditaa-diagram\] warning: conversion failed/);
    assert.deepEqual(fs.readdirSync(path.join(dir, ".imggen")), []);
  });
}

test("unterminated blocks and invalid closing fences are untouched", (t) => {
  const dir = setup(t);
  const spawn = renderer(t);
  const md = `\`\`\`ditaa\n${content}\`\`\`not-a-closing-fence\n`;
  assert.equal(preprocess(md, { inputDir: dir }), md);
  assert.equal(spawn.mock.callCount(), 0);
});

test("ditaa examples inside other fences stay literal", (t) => {
  const dir = setup(t);
  const spawn = renderer(t);
  for (const md of [`\`\`\`\`markdown\n${fence()}\`\`\`\`\n`, `~~~markdown\n${fence()}~~~\n`]) {
    assert.equal(preprocess(md, { inputDir: dir }), md);
  }
  assert.equal(spawn.mock.callCount(), 0);
});

test("real ditaa CLI creates a PNG without a display", { skip: !process.env.DITAA_SMOKE_TEST }, (t) => {
  const dir = setup(t);
  const png = path.join(dir, "smoke.png");
  convertToImg(content, png);
  assert.equal(fs.readFileSync(png).subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
  assert.equal(fs.existsSync(path.join(dir, "smoke.ditaa")), false);
});

test("container preprocessing pipeline loads ditaa and writes rendered Markdown", { skip: !process.env.DITAA_SMOKE_TEST }, (t) => {
  const dir = setup(t);
  const input = path.join(dir, "deck.md");
  fs.writeFileSync(input, `---\nmarp: true\n---\n${fence()}`);
  const pipeline = path.resolve(__dirname, "../../../bin/marp-preprocess.mjs");
  const result = cp.spawnSync(process.execPath, [pipeline, input], {
    cwd: dir,
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, "");
  const output = fs.readFileSync(path.resolve(dir, result.stdout.trim()), "utf8");
  assert.match(output, /!\[\]\(\.imggen\/ditaa-[a-f0-9]{64}\.png\)/);
  const png = path.join(dir, imagePath(content));
  assert.equal(fs.readFileSync(png).subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
});
