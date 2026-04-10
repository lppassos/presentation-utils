"use strict";

const path = require("node:path");
const fs = require("node:fs");
const cp = require("node:child_process");

/**
 * Returns true when the PNG needs to be (re-)generated:
 * - the PNG does not exist yet, OR
 * - the .drawio source is newer than the existing PNG.
 *
 * @param {string} drawioAbsPath  Absolute path to the .drawio source file.
 * @param {string} pngAbsPath     Absolute path to the target .png file.
 * @returns {boolean}
 */
function conversionNeeded(drawioAbsPath, pngAbsPath) {
  if (!fs.existsSync(pngAbsPath)) return true;
  const drawioMtime = fs.statSync(drawioAbsPath).mtimeMs;
  const pngMtime = fs.statSync(pngAbsPath).mtimeMs;
  return drawioMtime > pngMtime;
}

/**
 * Exports a .drawio file to a transparent PNG using headless draw.io.
 * Throws an Error when draw.io exits with a non-zero status.
 *
 * @param {string} drawioAbsPath  Absolute path to the .drawio source file.
 * @param {string} pngAbsPath     Absolute path where the PNG will be written.
 */
function convertToPng(drawioAbsPath, pngAbsPath) {
  fs.mkdirSync(path.dirname(pngAbsPath), { recursive: true });

  const cmd = "xvfb-run";
  const args = [
    "-a",
    "drawio",
    "--no-sandbox",
    "-x",
    "-f",
    "png",
    "--transparent",
    "-o",
    pngAbsPath,
    drawioAbsPath,
  ];

  const result = cp.spawnSync(cmd, args, { encoding: "utf8" });

  if (result.status !== 0) {
    const output = (result.stdout || "") + (result.stderr || "");
    throw new Error(
      `drawio export failed for ${drawioAbsPath} (exit ${result.status}): ${output.trim()}`
    );
  }
}

/**
 * Marp pre-processor for draw.io images.
 *
 * Scans `markdownText` for standard Markdown image references whose `src`
 * ends in `.drawio`, exports each referenced diagram to a transparent PNG
 * under `<inputDir>/.imggen/<basename>.png`, and rewrites the src to point
 * at that PNG.
 *
 * Conversion is skipped when an up-to-date PNG already exists.  If a
 * conversion fails, a warning is printed to stderr and the original `.drawio`
 * reference is left untouched (no crash).
 *
 * @param {string} markdownText  The raw markdown content.
 * @param {{ inputDir: string }} context
 * @returns {string}  The (possibly rewritten) markdown content.
 */
function preprocess(markdownText, { inputDir }) {
  // Match standard Markdown image syntax: ![alt text](path.drawio)
  // The path may contain any characters except ')' and must end with .drawio
  // (case-insensitive).
  const imageRegex = /!\[([^\]]*)\]\(([^)]+\.drawio)\)/gi;

  return markdownText.replace(imageRegex, (match, alt, src) => {
    const drawioAbsPath = path.resolve(inputDir, src);

    if (!fs.existsSync(drawioAbsPath)) {
      process.stderr.write(
        `[drawio-image] warning: file not found, skipping: ${drawioAbsPath}\n`
      );
      return match;
    }

    const basename = path.basename(src, path.extname(src));
    const pngRelPath = path.join(".imggen", `${basename}.png`);
    const pngAbsPath = path.join(inputDir, pngRelPath);

    if (conversionNeeded(drawioAbsPath, pngAbsPath)) {
      try {
        convertToPng(drawioAbsPath, pngAbsPath);
      } catch (err) {
        process.stderr.write(
          `[drawio-image] warning: conversion failed, skipping: ${err.message}\n`
        );
        return match;
      }
    }

    // Normalise to forward slashes so the path is valid in Markdown on all platforms.
    const pngRelPathNormalised = pngRelPath.replace(/\\/g, "/");
    return `![${alt}](${pngRelPathNormalised})`;
  });
}

module.exports = { preprocess, conversionNeeded, convertToPng };
