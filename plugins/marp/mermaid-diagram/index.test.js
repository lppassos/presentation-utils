"use strict";

/**
 * Unit tests for plugins/marp/mermaid-diagram/index.js
 *
 * Run with:  node --test plugins/marp/mermaid-diagram/index.test.js
 */

const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const fs = require("node:fs");
const os = require("node:os");
const crypto = require("node:crypto");

// ---------------------------------------------------------------------------
// Helper: create a temporary directory for each test.
// ---------------------------------------------------------------------------
function makeTmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "mermaid-diagram-test-"));
}

function touchFile(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, "");
}

// ---------------------------------------------------------------------------
// Load module under test.
// ---------------------------------------------------------------------------
const mermaidDiagram = require("./index.js");

// ---------------------------------------------------------------------------
// Retrieve child_process as seen by the plugin so we can monkey-patch it.
// ---------------------------------------------------------------------------
const cp = require("node:child_process");

function withSpawnSync(fakeFn, body) {
  const original = cp.spawnSync;
  cp.spawnSync = fakeFn;
  try {
    return body();
  } finally {
    cp.spawnSync = original;
  }
}

// ---------------------------------------------------------------------------
// Helper: compute expected hash for a given mermaid content string.
// ---------------------------------------------------------------------------
function hashOf(content) {
  return crypto.createHash("sha256").update(content).digest("hex");
}

// ---------------------------------------------------------------------------
// Tests for conversionNeeded
// ---------------------------------------------------------------------------

test("conversionNeeded: returns true when PNG does not exist", () => {
  const dir = makeTmpDir();
  const png = path.join(dir, "mermaid-abc.png");
  assert.equal(mermaidDiagram.conversionNeeded(png), true);
  fs.rmSync(dir, { recursive: true });
});

test("conversionNeeded: returns false when PNG already exists", () => {
  const dir = makeTmpDir();
  const png = path.join(dir, "mermaid-abc.png");
  touchFile(png);
  assert.equal(mermaidDiagram.conversionNeeded(png), false);
  fs.rmSync(dir, { recursive: true });
});

// ---------------------------------------------------------------------------
// Tests for preprocess
// ---------------------------------------------------------------------------

test("preprocess: markdown with no mermaid block is returned unchanged", () => {
  const md = "# Slide\n\n![photo](photo.png)\n\nSome text.\n";
  const result = mermaidDiagram.preprocess(md, { inputDir: os.tmpdir() });
  assert.equal(result, md);
});

test("preprocess: mermaid block is replaced with .imggen PNG image reference on success", () => {
  const dir = makeTmpDir();
  const content = "graph TD\n  A --> B\n";
  const md = "```mermaid\n" + content + "```\n";

  const spawnCalled = { value: false };
  const result = withSpawnSync(
    (_cmd, _args) => {
      spawnCalled.value = true;
      // Create the PNG so the plugin sees it was written.
      const hash = hashOf(content);
      const png = path.join(dir, ".imggen", `mermaid-${hash}.png`);
      fs.mkdirSync(path.dirname(png), { recursive: true });
      fs.writeFileSync(png, "");
      return { status: 0, stdout: "", stderr: "" };
    },
    () => mermaidDiagram.preprocess(md, { inputDir: dir })
  );

  assert.equal(spawnCalled.value, true, "spawnSync should have been called");
  const hash = hashOf(content);
  assert.match(result, new RegExp(`\\.imggen/mermaid-${hash}\\.png`));
  assert.doesNotMatch(result, /```mermaid/);
  fs.rmSync(dir, { recursive: true });
});

test("preprocess: conversion is skipped (cache hit) when PNG already exists", () => {
  const dir = makeTmpDir();
  const content = "graph TD\n  A --> B\n";
  const hash = hashOf(content);
  const png = path.join(dir, ".imggen", `mermaid-${hash}.png`);
  touchFile(png);

  const md = "```mermaid\n" + content + "```\n";

  const spawnCalled = { value: false };
  const result = withSpawnSync(
    () => {
      spawnCalled.value = true;
      return { status: 0, stdout: "", stderr: "" };
    },
    () => mermaidDiagram.preprocess(md, { inputDir: dir })
  );

  assert.equal(spawnCalled.value, false, "spawnSync should NOT have been called");
  assert.match(result, new RegExp(`\\.imggen/mermaid-${hash}\\.png`));
  fs.rmSync(dir, { recursive: true });
});

test("preprocess: original fenced block is left unchanged when mmdc exits non-zero", () => {
  const dir = makeTmpDir();
  const content = "graph TD\n  A --> B\n";
  const md = "```mermaid\n" + content + "```\n";

  const result = withSpawnSync(
    () => ({ status: 1, stdout: "error output", stderr: "" }),
    () => mermaidDiagram.preprocess(md, { inputDir: dir })
  );

  assert.match(result, /```mermaid/);
  assert.doesNotMatch(result, /\.imggen/);
  fs.rmSync(dir, { recursive: true });
});

test("preprocess: multiple mermaid blocks are all replaced independently", () => {
  const dir = makeTmpDir();
  const content1 = "graph TD\n  A --> B\n";
  const content2 = "sequenceDiagram\n  Alice->>Bob: Hello\n";
  const hash1 = hashOf(content1);
  const hash2 = hashOf(content2);
  const md =
    "# Slide 1\n\n```mermaid\n" +
    content1 +
    "```\n\n# Slide 2\n\n```mermaid\n" +
    content2 +
    "```\n";

  const result = withSpawnSync(
    (_cmd, args) => {
      // Extract the output path from args and create the PNG.
      const outIdx = args.indexOf("-o");
      if (outIdx !== -1) {
        const outPath = args[outIdx + 1];
        fs.mkdirSync(path.dirname(outPath), { recursive: true });
        fs.writeFileSync(outPath, "");
      }
      return { status: 0, stdout: "", stderr: "" };
    },
    () => mermaidDiagram.preprocess(md, { inputDir: dir })
  );

  assert.match(result, new RegExp(`\\.imggen/mermaid-${hash1}\\.png`));
  assert.match(result, new RegExp(`\\.imggen/mermaid-${hash2}\\.png`));
  assert.doesNotMatch(result, /```mermaid/);
  fs.rmSync(dir, { recursive: true });
});

test("preprocess: two identical mermaid blocks resolve to the same PNG path", () => {
  const dir = makeTmpDir();
  const content = "graph TD\n  A --> B\n";
  const hash = hashOf(content);
  const md =
    "```mermaid\n" + content + "```\n\n```mermaid\n" + content + "```\n";

  let spawnCount = 0;
  const result = withSpawnSync(
    (_cmd, args) => {
      spawnCount++;
      const outIdx = args.indexOf("-o");
      if (outIdx !== -1) {
        const outPath = args[outIdx + 1];
        fs.mkdirSync(path.dirname(outPath), { recursive: true });
        fs.writeFileSync(outPath, "");
      }
      return { status: 0, stdout: "", stderr: "" };
    },
    () => mermaidDiagram.preprocess(md, { inputDir: dir })
  );

  // Both references should point at the same hash-derived PNG.
  const matches = [...result.matchAll(new RegExp(`\\.imggen/mermaid-${hash}\\.png`, "g"))];
  assert.equal(matches.length, 2, "Both blocks should reference the same PNG");
  // mmdc should only have been called once (second block is a cache hit).
  assert.equal(spawnCount, 1, "mmdc should only be invoked once for identical content");
  fs.rmSync(dir, { recursive: true });
});

test("preprocess: spawnSync is called as mmdc with -i and -o flags", () => {
  const dir = makeTmpDir();
  const content = "graph TD\n  A --> B\n";
  const md = "```mermaid\n" + content + "```\n";

  let capturedCmd = null;
  let capturedArgs = null;
  withSpawnSync(
    (cmd, args) => {
      capturedCmd = cmd;
      capturedArgs = args;
      const outIdx = args.indexOf("-o");
      if (outIdx !== -1) {
        const outPath = args[outIdx + 1];
        fs.mkdirSync(path.dirname(outPath), { recursive: true });
        fs.writeFileSync(outPath, "");
      }
      return { status: 0, stdout: "", stderr: "" };
    },
    () => mermaidDiagram.preprocess(md, { inputDir: dir })
  );

  assert.equal(capturedCmd, "mmdc", "command should be mmdc (no xvfb wrapper)");
  assert.ok(capturedArgs !== null, "spawnSync should have been called");
  assert.ok(capturedArgs.includes("-i"), "args should include -i");
  assert.ok(capturedArgs.includes("-o"), "args should include -o");

  // The -i argument should be a .mmd file path.
  const inIdx = capturedArgs.indexOf("-i");
  assert.match(capturedArgs[inIdx + 1], /\.mmd$/, "-i target should be a .mmd file");

  // The -o argument should be the expected PNG path.
  const hash = hashOf(content);
  const outIdx = capturedArgs.indexOf("-o");
  assert.match(
    capturedArgs[outIdx + 1],
    new RegExp(`mermaid-${hash}\\.png$`),
    "-o target should be the hash-derived PNG"
  );

  fs.rmSync(dir, { recursive: true });
});
