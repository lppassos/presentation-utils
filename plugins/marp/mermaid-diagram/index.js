"use strict";

const path = require("node:path");
const fs = require("node:fs");
const cp = require("node:child_process");
const crypto = require("node:crypto");

/**
 * Returns true when the PNG needs to be (re-)generated, i.e. when it does not
 * yet exist.  Because the PNG path is derived from a SHA-256 hash of the
 * mermaid block content, existence is sufficient to prove the content has not
 * changed.
 *
 * @param {string} pngAbsPath  Absolute path to the target .png file.
 * @returns {boolean}
 */
function conversionNeeded(pngAbsPath) {
  return !fs.existsSync(pngAbsPath);
}

/**
 * Renders a Mermaid diagram to a PNG using the mmdc CLI.
 *
 * Writes `mermaidContent` to a temporary `.mmd` file inside the same directory
 * as `pngAbsPath`, invokes `mmdc -i <tmp.mmd> -o <pngAbsPath>`, removes the
 * temp file, and throws an Error when mmdc exits with a non-zero status.
 *
 * @param {string} mermaidContent  Raw mermaid diagram source.
 * @param {string} pngAbsPath      Absolute path where the PNG will be written.
 */
function convertToImg(mermaidContent, pngAbsPath) {
  fs.mkdirSync(path.dirname(pngAbsPath), { recursive: true });

  const tmpMmd = pngAbsPath.replace(/\.png$/, ".mmd");
  fs.writeFileSync(tmpMmd, mermaidContent, "utf8");

  const mmdcArgs = [
    "-i",
    tmpMmd,
    "-o",
    pngAbsPath,
    "-p",
    "/usr/local/lib/puppeteer-config.json",
  ];
  try {
    const result = cp.spawnSync("mmdc", mmdcArgs, {
      encoding: "utf8",
    });

    if (result.status !== 0) {
      const output = (result.stdout || "") + (result.stderr || "");
      throw new Error(
        `mmdc export failed (exit ${result.status}): ${output.trim()}`,
      );
    }
  } finally {
    // Always remove the temp file, even on failure.
    try {
      fs.unlinkSync(tmpMmd);
    } catch (_) {
      // Ignore cleanup errors.
    }
  }
}

/**
 * Marp pre-processor for Mermaid diagrams.
 *
 * Scans `markdownText` for fenced code blocks tagged `mermaid`, renders each
 * one to a PNG under `<inputDir>/.imggen/mermaid-<sha256>.png` using mmdc, and
 * replaces the fenced block with a standard Markdown image reference pointing
 * at the generated PNG.
 *
 * Conversion is skipped when an up-to-date PNG already exists (content-hash
 * cache).  If a conversion fails, a warning is printed to stderr and the
 * original fenced block is left untouched (no crash).
 *
 * @param {string} markdownText       The raw markdown content.
 * @param {{ inputDir: string }} context
 * @returns {string}  The (possibly rewritten) markdown content.
 */
function preprocess(markdownText, { inputDir }) {
  // Match fenced mermaid blocks: ```mermaid\n<content>\n```
  // The closing ``` must be on its own line.
  const mermaidRegex = /^```mermaid( \[[^\]]*\])?\r?\n([\s\S]*?)^```/gm;

  return markdownText.replace(mermaidRegex, (match, options, content) => {
    const hash = crypto.createHash("sha256").update(content).digest("hex");
    const pngRelPath = path.join(".imggen", `mermaid-${hash}.png`);
    const pngAbsPath = path.join(inputDir, pngRelPath);

    if (conversionNeeded(pngAbsPath)) {
      try {
        convertToImg(content, pngAbsPath);
      } catch (err) {
        process.stderr.write(
          `[mermaid-diagram] warning: conversion failed, skipping: ${err.message}\n`,
        );
        return match;
      }
    }

    // Normalise to forward slashes so the path is valid in Markdown on all platforms.
    const pngRelPathNormalised = pngRelPath.replace(/\\/g, "/");
    return `![${options}](${pngRelPathNormalised})`;
  });
}

module.exports = { preprocess, conversionNeeded, convertToImg };
