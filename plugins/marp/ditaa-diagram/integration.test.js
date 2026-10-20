"use strict";

// Run inside the built container with DITAA_INTEGRATION=1.
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");
const { preprocess } = require("./index.js");

test("real ditaa PNGs have transparent backgrounds and inverted RGB with identical alpha", {
  skip: process.env.DITAA_INTEGRATION !== "1",
}, t => {
  const inputDir = fs.mkdtempSync(path.join(os.tmpdir(), "ditaa-pixels-"));
  t.after(() => fs.rmSync(inputDir, { recursive: true, force: true }));
  const source = "+--------+\n| Source |\n+--------+\n";
  const render = options => {
    const markdown = `\`\`\`ditaa [${options}]\n${source}\`\`\`\n`;
    const result = preprocess(markdown, { inputDir });
    const image = result.match(/\]\(([^)]+)\)/);
    assert.ok(image, `expected image reference, got ${result}`);
    const pixels = cp.spawnSync("magick", [path.join(inputDir, image[1]), "-depth", "8", "rgba:-"]);
    assert.equal(pixels.status, 0, pixels.stderr.toString());
    return pixels.stdout;
  };
  for (const options of ["", "transparent"]) {
    const original = render(options);
    const inverted = render(`${options} invert`);
    assert.ok(original.length > 0);
    assert.equal(original.length, inverted.length);
    assert.equal(original[3], options ? 0 : 255, "canvas corner alpha");
    let visiblePixels = 0;
    for (let i = 0; i < original.length; i += 4) {
      assert.equal(original[i + 3], inverted[i + 3], "alpha must not change");
      if (!original[i + 3]) continue; // hidden RGB may be normalized by PNG encoding
      visiblePixels++;
      for (let channel = 0; channel < 3; channel++) {
        assert.ok(Math.abs(original[i + channel] + inverted[i + channel] - 255) <= 1,
          `RGB not inverted at pixel ${i / 4}`);
      }
    }
    assert.ok(visiblePixels > 0, "diagram itself must remain visible");
  }

  // Exercise the actual registered preprocessing pipeline, not a test double.
  const input = path.join(inputDir, "slides.md");
  fs.writeFileSync(input, `\`\`\`ditaa [transparent invert]\n${source}\`\`\`\n`);
  const pipeline = cp.spawnSync("node", ["/usr/local/lib/marp-preprocess.mjs", input], {
    cwd: inputDir, encoding: "utf8",
  });
  assert.equal(pipeline.status, 0, pipeline.stderr);
  assert.match(fs.readFileSync(path.resolve(inputDir, pipeline.stdout.trim()), "utf8"), /^!\[\]\(\.imggen\/ditaa-/);
});
