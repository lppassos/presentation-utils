"use strict";

const path = require("node:path");
const fs = require("node:fs");
const cp = require("node:child_process");
const crypto = require("node:crypto");

function run(command, args) {
  const result = cp.spawnSync(command, args, { encoding: "utf8" });
  if (result.error || result.status !== 0) {
    throw new Error(
      `${command} failed: ${
        result.error?.message ||
        ((result.stdout || "") + (result.stderr || "")).trim() ||
        `exit ${result.status}`
      }`,
    );
  }
}

/** Render to a temporary PNG so a failed inversion never poisons the cache. */
function convertToImg(content, pngPath, { transparent, invert }) {
  fs.mkdirSync(path.dirname(pngPath), { recursive: true });
  const tempDir = fs.mkdtempSync(path.join(path.dirname(pngPath), ".ditaa-"));
  const source = path.join(tempDir, "diagram.txt");
  const rendered = path.join(tempDir, "diagram.png");
  try {
    fs.writeFileSync(source, content, "utf8");
    const args = ["--encoding", "UTF-8"];
    if (transparent) args.push("--transparent", "--no-shadows");
    run("ditaa", [...args, source, rendered]);
    if (invert) {
      // Negate RGB only: the alpha channel must remain unchanged.
      run("magick", [
        rendered,
        "-channel",
        "RGB",
        "-negate",
        "+channel",
        rendered,
      ]);
    }
    fs.renameSync(rendered, pngPath);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

/** Replace ditaa fences with cached PNGs, retaining Marp image options. */
function preprocess(markdownText, { inputDir }) {
  const fence =
    /^```ditaa(?:[ \t]*\[([^\]\r\n]*)\])?[ \t]*\r?\n([\s\S]*?)^```[ \t]*(?=\r?$)/gm;
  return markdownText.replace(fence, (match, options = "", content) => {
    const tokens = options
      .trim()
      .split(/[\s,]+/)
      .filter(Boolean);
    const transparent = tokens.includes("transparent");
    const invert = tokens.includes("invert");
    const hash = crypto
      .createHash("sha256")
      .update(JSON.stringify({ content, transparent, invert }))
      .digest("hex");
    const relativePath = `.imggen/ditaa-${hash}.png`;
    const pngPath = path.join(inputDir, relativePath);
    if (!fs.existsSync(pngPath)) {
      try {
        convertToImg(content, pngPath, { transparent, invert });
      } catch (err) {
        process.stderr.write(
          `[ditaa-diagram] warning: conversion failed, skipping: ${err.message}\n`,
        );
        return match;
      }
    }
    const imageOptions = tokens.filter(
      (token) => token !== "transparent" && token !== "invert",
    );
    return `![${imageOptions.join(" ")}](${relativePath})`;
  });
}

module.exports = { preprocess, convertToImg };
