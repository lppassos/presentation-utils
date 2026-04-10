#!/usr/bin/env node
/**
 * marp-preprocess.mjs
 *
 * Pre-processing pipeline for Marp presentations.
 *
 * Usage:
 *   node marp-preprocess.mjs <absolute-path-to-input.md>
 *
 * Reads the given Markdown file, runs it through all registered preprocessor
 * modules in sequence, writes the result to a temporary file next to the
 * original (so that relative image paths continue to resolve correctly), and
 * prints the temp-file path to stdout.
 *
 * Adding a new preprocessor is as simple as:
 *   1. Create a module under /plugins/marp/<name>/index.js that exports
 *      { preprocess(markdownText, { inputDir }) }.
 *   2. Import it below and add it to the `preprocessors` array.
 *
 * Exit codes:
 *   0  Success – temp file path printed to stdout.
 *   1  Error   – message printed to stderr.
 */

import { createRequire } from "node:module";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, basename, extname } from "node:path";
const { randomBytes } = await import("node:crypto");

// Use createRequire so we can load CommonJS plugin modules from absolute paths.
const require = createRequire(import.meta.url);

// ---------------------------------------------------------------------------
// Registered preprocessors (extend this list to add new ones).
// ---------------------------------------------------------------------------
const {
  preprocess: drawioPreprocess,
} = require("/plugins/marp/drawio-image/index.js");

const {
  preprocess: mermaidPreprocess,
} = require("/plugins/marp/mermaid-diagram/index.js");

const preprocessors = [drawioPreprocess, mermaidPreprocess];

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const inputPath = process.argv[2];

if (!inputPath) {
  process.stderr.write(
    "Usage: node marp-preprocess.mjs <absolute-path-to-input.md>\n",
  );
  process.exit(1);
}

function random_suffix(length = 8) {
  const chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = randomBytes(length);
  let result = "";
  for (let i = 0; i < length; i++) {
    result += chars.charAt(bytes[i] % chars.length);
  }
  return result;
}

try {
  const inputDir = dirname(inputPath);
  let markdownText = readFileSync(inputPath, "utf8");

  for (const preprocessor of preprocessors) {
    // Each preprocessor may be sync or async; await to support both.
    markdownText = await preprocessor(markdownText, { inputDir });
  }

  // Write the processed content to a temp file inside the same directory as
  // the original so that relative paths (images, etc.) resolve identically.
  const ext = extname(basename(inputPath)) || ".md";
  const suffix = random_suffix();
  const tmpFile = join("./", `preprocessed_${suffix}${ext}`);
  writeFileSync(tmpFile, markdownText, "utf8");

  process.stdout.write(tmpFile + "\n");
  process.exit(0);
} catch (err) {
  process.stderr.write(`[marp-preprocess] error: ${err.message}\n`);
  process.exit(1);
}
