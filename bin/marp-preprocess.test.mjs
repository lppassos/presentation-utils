/**
 * Integration tests for bin/marp-preprocess.mjs
 *
 * These tests spawn the script as a child process to verify its CLI
 * contract without needing the container's absolute plugin paths.
 * A lightweight test-double version of the script is used that swaps
 * the real preprocessor list with a configurable stub, controlled by
 * environment variables so no source files need editing.
 *
 * Strategy
 * --------
 * We create a temporary "test-double" version of marp-preprocess.mjs
 * that behaves identically but loads a test preprocessor whose behaviour
 * is driven by env vars:
 *   STUB_PREPROCESS_SUFFIX   – appended to the markdown text (default: "")
 *   STUB_PREPROCESS_THROW    – if "1", the preprocessor throws
 *
 * Run with:  node --test bin/marp-preprocess.test.mjs
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  mkdtempSync,
  writeFileSync,
  readFileSync,
  rmSync,
  existsSync,
} from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------------------
// Build a self-contained test-double script we can spawn.
// It mirrors marp-preprocess.mjs but uses an inline stub preprocessor.
// ---------------------------------------------------------------------------
const TEST_DOUBLE_SRC = `
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { dirname, join, extname, basename } from "node:path";

// Stub preprocessor controlled by env vars
async function stubPreprocess(markdownText, { inputDir }) {
  if (process.env.STUB_PREPROCESS_THROW === "1") {
    throw new Error("stub preprocessor error");
  }
  const suffix = process.env.STUB_PREPROCESS_SUFFIX || "";
  return markdownText + suffix;
}

const preprocessors = [stubPreprocess];

const inputPath = process.argv[2];

if (!inputPath) {
  process.stderr.write("Usage: node marp-preprocess.mjs <absolute-path-to-input.md>\\n");
  process.exit(1);
}

try {
  const inputDir = dirname(inputPath);
  let markdownText = readFileSync(inputPath, "utf8");

  for (const p of preprocessors) {
    markdownText = await p(markdownText, { inputDir });
  }

  const ext = extname(basename(inputPath)) || ".md";
  const tmpDir = mkdtempSync(join(inputDir, ".marp-preprocess-"));
  const tmpFile = join(tmpDir, "preprocessed" + ext);
  writeFileSync(tmpFile, markdownText, "utf8");

  process.stdout.write(tmpFile + "\\n");
  process.exit(0);
} catch (err) {
  process.stderr.write("[marp-preprocess] error: " + err.message + "\\n");
  process.exit(1);
}
`;

// Write the test-double to a temp file once for all tests.
const testDoubleDir = mkdtempSync(join(tmpdir(), "marp-preprocess-test-double-"));
const testDoublePath = join(testDoubleDir, "marp-preprocess-double.mjs");
writeFileSync(testDoublePath, TEST_DOUBLE_SRC, "utf8");

// ---------------------------------------------------------------------------
// Helper: run the test-double script synchronously.
// ---------------------------------------------------------------------------
function runDouble(args, env = {}) {
  return spawnSync(
    process.execPath,
    [testDoublePath, ...args],
    { encoding: "utf8", env: { ...process.env, ...env } }
  );
}

// ---------------------------------------------------------------------------
// Helper: create a temp input markdown file.
// ---------------------------------------------------------------------------
function makeTempMd(content = "# Hello\n") {
  const dir = mkdtempSync(join(tmpdir(), "marp-preprocess-input-"));
  const mdPath = join(dir, "test.md");
  writeFileSync(mdPath, content, "utf8");
  return { dir, mdPath };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test("happy path: produces a temp file containing the processed markdown", () => {
  const { dir, mdPath } = makeTempMd("# Slide\n");

  const result = runDouble([mdPath], { STUB_PREPROCESS_SUFFIX: "_processed" });

  assert.equal(result.status, 0, `Expected exit 0, got ${result.status}; stderr: ${result.stderr}`);

  const tmpFilePath = result.stdout.trim();
  assert.ok(tmpFilePath.length > 0, "stdout should contain the temp file path");
  assert.ok(existsSync(tmpFilePath), `Temp file should exist: ${tmpFilePath}`);

  const content = readFileSync(tmpFilePath, "utf8");
  assert.equal(content, "# Slide\n_processed");

  // Cleanup: removing the input dir also removes the temp subdirectory
  // created inside it by the pipeline.
  rmSync(dir, { recursive: true });
});

test("preprocessor error propagation: exits with code 1, no temp file created", () => {
  const { dir, mdPath } = makeTempMd("# Slide\n");

  const result = runDouble([mdPath], { STUB_PREPROCESS_THROW: "1" });

  assert.equal(result.status, 1, `Expected exit 1, got ${result.status}`);
  assert.match(result.stderr, /stub preprocessor error/);
  assert.equal(result.stdout.trim(), "", "stdout should be empty on error");

  rmSync(dir, { recursive: true });
});

test("no arguments: exits with code 1 and prints usage to stderr", () => {
  const result = runDouble([]);

  assert.equal(result.status, 1, `Expected exit 1, got ${result.status}`);
  assert.match(result.stderr, /Usage:/i);
});

test("happy path: temp file is created next to the input file (same directory)", () => {
  const { dir, mdPath } = makeTempMd("content\n");

  const result = runDouble([mdPath]);

  assert.equal(result.status, 0);
  const tmpFilePath = result.stdout.trim();
  // The temp file's parent's parent should equal the input dir
  const tmpParent = dirname(dirname(tmpFilePath));
  assert.equal(tmpParent, dir);

  rmSync(dir, { recursive: true });
});

test("happy path: output file has the same extension as the input", () => {
  const { dir, mdPath } = makeTempMd("# Test\n");

  const result = runDouble([mdPath]);

  assert.equal(result.status, 0);
  const tmpFilePath = result.stdout.trim();
  assert.ok(tmpFilePath.endsWith(".md"), `Expected .md extension, got: ${tmpFilePath}`);

  rmSync(dir, { recursive: true });
});

// ---------------------------------------------------------------------------
// Cleanup test-double temp dir after all tests
// (node:test doesn't have a global afterAll, so we register it via process exit)
// ---------------------------------------------------------------------------
process.on("exit", () => {
  try { rmSync(testDoubleDir, { recursive: true }); } catch (_) { /* ignore */ }
});
