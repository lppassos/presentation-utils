"use strict";

const path = require("node:path");
const fs = require("node:fs");
const cp = require("node:child_process");
const crypto = require("node:crypto");

function conversionNeeded(pngAbsPath) {
  return !fs.existsSync(pngAbsPath);
}

/** Render UTF-8 ASCII art with the ditaa CLI bundled in the container. */
function convertToImg(content, pngAbsPath) {
  fs.mkdirSync(path.dirname(pngAbsPath), { recursive: true });
  const tmpDir = fs.mkdtempSync(path.join(path.dirname(pngAbsPath), ".ditaa-"));
  const tmpSource = path.join(tmpDir, "source.ditaa");
  const tmpPng = path.join(tmpDir, "output.png");
  try {
    fs.writeFileSync(tmpSource, content, "utf8");
    const result = cp.spawnSync(
      // Debian's /usr/bin/ditaa is a JAR, not a shell launcher. Invoking Java
      // explicitly avoids relying on binfmt_misc support inside Docker.
      "java",
      ["-Djava.awt.headless=true", "-jar", "/usr/bin/ditaa", "--overwrite", "--encoding", "UTF-8", tmpSource, tmpPng],
      { encoding: "utf8" },
    );
    if (result.error) throw result.error;
    if (result.status !== 0) {
      const output = (result.stdout || "") + (result.stderr || "");
      throw new Error(`ditaa export failed (exit ${result.status}): ${output.trim()}`);
    }
    if (!fs.existsSync(tmpPng)) {
      throw new Error("ditaa did not create the requested PNG");
    }
    // Publish only completed images. Concurrent renders own separate temp files.
    fs.renameSync(tmpPng, pngAbsPath);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

/**
 * Replace fenced ditaa blocks with content-addressed PNG references, just like
 * the Mermaid preprocessor. Optional [width:... height:...] image options are
 * passed through to Marp. Failed renders leave the original fence untouched.
 */
function preprocess(markdownText, { inputDir }) {
  function renderBlock(match, options, content) {
    const hash = crypto.createHash("sha256").update(content).digest("hex");
    const pngRelPath = `.imggen/ditaa-${hash}.png`;
    const pngAbsPath = path.join(inputDir, pngRelPath);

    if (conversionNeeded(pngAbsPath)) {
      try {
        convertToImg(content, pngAbsPath);
      } catch (err) {
        process.stderr.write(
          `[ditaa-diagram] warning: conversion failed, skipping: ${err.message}\n`,
        );
        return match;
      }
    }

    return `![${options || ""}](${pngRelPath})`;
  }

  // Walk complete Markdown fences so examples inside longer fences (and other
  // code blocks) remain literal rather than being rendered as diagrams.
  const opening = /^ {0,3}(`{3,}|~{3,})([^\r\n]*)\r?\n/gm;
  let result = "";
  let cursor = 0;
  let block;
  while ((block = opening.exec(markdownText))) {
    const marker = block[1];
    const closing = new RegExp(`^ {0,3}${marker[0]}{${marker.length},}[ \\t]*(?=\\r?$)`, "gm");
    closing.lastIndex = opening.lastIndex;
    const end = closing.exec(markdownText);
    if (!end) break;
    const info = /^ditaa(?:[ \t]+\[([^\]\r\n]*)\])?[ \t]*$/.exec(block[2]);
    const blockEnd = closing.lastIndex;
    result += markdownText.slice(cursor, block.index);
    const original = markdownText.slice(block.index, blockEnd);
    result += info
      ? renderBlock(original, info[1], markdownText.slice(opening.lastIndex, end.index))
      : original;
    cursor = blockEnd;
    opening.lastIndex = blockEnd;
  }
  return result + markdownText.slice(cursor);
}

module.exports = { preprocess, conversionNeeded, convertToImg };
