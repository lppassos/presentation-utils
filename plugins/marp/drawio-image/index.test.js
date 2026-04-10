"use strict";

/**
 * Unit tests for plugins/marp/drawio-image/index.js
 *
 * Run with:  node --test plugins/marp/drawio-image/index.test.js
 */

const { test, mock } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const fs = require("node:fs");
const os = require("node:os");

// ---------------------------------------------------------------------------
// Helper: create a temporary directory with real files so we can test
// mtime-based caching without touching any real project files.
// ---------------------------------------------------------------------------
function makeTmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "drawio-image-test-"));
}

function touchFile(filePath, mtimeOffset = 0) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, "");
  if (mtimeOffset !== 0) {
    const t = new Date(Date.now() + mtimeOffset);
    fs.utimesSync(filePath, t, t);
  }
}

// ---------------------------------------------------------------------------
// We need to intercept spawnSync calls.  Because the module caches the
// reference to child_process.spawnSync at require-time, we patch it on the
// module's copy of child_process by manipulating the module registry.
//
// Strategy: require the module, then replace its internal spawnSync via a
// thin wrapper that reads a test-controlled variable.
// ---------------------------------------------------------------------------

// Load the module under test.
const drawioImage = require("./index.js");

// ---------------------------------------------------------------------------
// Tests for conversionNeeded (internal, exported for testing)
// ---------------------------------------------------------------------------

test("conversionNeeded: returns true when PNG does not exist", () => {
  const dir = makeTmpDir();
  const drawio = path.join(dir, "a.drawio");
  const png = path.join(dir, "a.png");
  touchFile(drawio);
  assert.equal(drawioImage.conversionNeeded(drawio, png), true);
  fs.rmSync(dir, { recursive: true });
});

test("conversionNeeded: returns true when drawio is newer than PNG", () => {
  const dir = makeTmpDir();
  const drawio = path.join(dir, "a.drawio");
  const png = path.join(dir, "a.png");
  // PNG is 10 s in the past, drawio is now
  touchFile(png, -10_000);
  touchFile(drawio, 0);
  assert.equal(drawioImage.conversionNeeded(drawio, png), true);
  fs.rmSync(dir, { recursive: true });
});

test("conversionNeeded: returns false when PNG is newer than drawio", () => {
  const dir = makeTmpDir();
  const drawio = path.join(dir, "a.drawio");
  const png = path.join(dir, "a.png");
  // drawio is 10 s in the past, PNG is now
  touchFile(drawio, -10_000);
  touchFile(png, 0);
  assert.equal(drawioImage.conversionNeeded(drawio, png), false);
  fs.rmSync(dir, { recursive: true });
});

// ---------------------------------------------------------------------------
// Tests for preprocess (the main exported function)
// We monkey-patch child_process.spawnSync via the module's require cache.
// ---------------------------------------------------------------------------

// Retrieve the child_process module as seen by the plugin (same cached reference).
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

test("preprocess: markdown without .drawio images is returned unchanged", () => {
  const md = "# Slide\n\n![photo](photo.png)\n\nSome text.\n";
  const result = drawioImage.preprocess(md, { inputDir: os.tmpdir() });
  assert.equal(result, md);
});

test("preprocess: rewrites .drawio src to .imggen PNG on successful conversion", () => {
  const dir = makeTmpDir();
  const drawioFile = path.join(dir, "arch.drawio");
  touchFile(drawioFile);

  const md = `# Slide\n\n![Arch](arch.drawio)\n`;

  const spawnCalled = { value: false };
  const result = withSpawnSync(
    (_cmd, _args) => {
      spawnCalled.value = true;
      return { status: 0, stdout: "", stderr: "" };
    },
    () => drawioImage.preprocess(md, { inputDir: dir })
  );

  assert.equal(spawnCalled.value, true, "spawnSync should have been called");
  assert.match(result, /\.imggen\/arch\.png/);
  assert.doesNotMatch(result, /arch\.drawio/);
  fs.rmSync(dir, { recursive: true });
});

test("preprocess: skips conversion (cache hit) when PNG is up-to-date", () => {
  const dir = makeTmpDir();
  const drawioFile = path.join(dir, "flow.drawio");
  const pngFile = path.join(dir, ".imggen", "flow.png");

  // drawio is old, PNG is fresh
  touchFile(drawioFile, -10_000);
  touchFile(pngFile, 0);

  const md = `![Flow](flow.drawio)\n`;

  const spawnCalled = { value: false };
  const result = withSpawnSync(
    () => {
      spawnCalled.value = true;
      return { status: 0, stdout: "", stderr: "" };
    },
    () => drawioImage.preprocess(md, { inputDir: dir })
  );

  assert.equal(spawnCalled.value, false, "spawnSync should NOT have been called");
  assert.match(result, /\.imggen\/flow\.png/);
  fs.rmSync(dir, { recursive: true });
});

test("preprocess: leaves .drawio reference unchanged when conversion fails", () => {
  const dir = makeTmpDir();
  const drawioFile = path.join(dir, "bad.drawio");
  touchFile(drawioFile);

  const md = `![Bad](bad.drawio)\n`;

  const result = withSpawnSync(
    () => ({ status: 1, stdout: "error output", stderr: "" }),
    () => drawioImage.preprocess(md, { inputDir: dir })
  );

  assert.match(result, /bad\.drawio/);
  assert.doesNotMatch(result, /\.imggen/);
  fs.rmSync(dir, { recursive: true });
});

test("preprocess: leaves .drawio reference unchanged when source file is missing", () => {
  const dir = makeTmpDir();
  // Do NOT create the drawio file
  const md = `![Missing](missing.drawio)\n`;

  const spawnCalled = { value: false };
  const result = withSpawnSync(
    () => {
      spawnCalled.value = true;
      return { status: 0 };
    },
    () => drawioImage.preprocess(md, { inputDir: dir })
  );

  assert.equal(spawnCalled.value, false, "spawnSync should NOT be called for missing files");
  assert.match(result, /missing\.drawio/);
  fs.rmSync(dir, { recursive: true });
});

test("preprocess: command passed to spawnSync includes --transparent flag", () => {
  const dir = makeTmpDir();
  const drawioFile = path.join(dir, "diagram.drawio");
  touchFile(drawioFile);

  const md = `![Diagram](diagram.drawio)\n`;

  let capturedArgs = null;
  withSpawnSync(
    (_cmd, args) => {
      capturedArgs = args;
      return { status: 0, stdout: "", stderr: "" };
    },
    () => drawioImage.preprocess(md, { inputDir: dir })
  );

  assert.ok(capturedArgs !== null, "spawnSync should have been called");
  assert.ok(
    capturedArgs.includes("--transparent"),
    `Expected --transparent in args but got: ${JSON.stringify(capturedArgs)}`
  );
  fs.rmSync(dir, { recursive: true });
});

test("preprocess: command passed to spawnSync uses xvfb-run with correct draw.io flags", () => {
  const dir = makeTmpDir();
  const drawioFile = path.join(dir, "diagram.drawio");
  touchFile(drawioFile);

  const md = `![Diagram](diagram.drawio)\n`;

  let capturedCmd = null;
  let capturedArgs = null;
  withSpawnSync(
    (cmd, args) => {
      capturedCmd = cmd;
      capturedArgs = args;
      return { status: 0, stdout: "", stderr: "" };
    },
    () => drawioImage.preprocess(md, { inputDir: dir })
  );

  assert.equal(capturedCmd, "xvfb-run");
  assert.ok(capturedArgs.includes("-a"));
  assert.ok(capturedArgs.includes("drawio"));
  assert.ok(capturedArgs.includes("--no-sandbox"));
  assert.ok(capturedArgs.includes("-x"));
  assert.ok(capturedArgs.includes("-f"));
  assert.ok(capturedArgs.includes("png"));
  assert.ok(capturedArgs.includes("--transparent"));
  fs.rmSync(dir, { recursive: true });
});
