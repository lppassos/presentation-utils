"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");

const customDiagram = require("./index.js");

test("parseCustomDiagramBlock ignores whitespace and detects radial-team", () => {
  const data = customDiagram.parseCustomDiagramBlock("\n  radial-team  \n\n Alice, Architect \n");

  assert.equal(data.type, "radial-team");
  assert.deepEqual(data.members, [{ name: "Alice", role: "Architect" }]);
});

test("parseCustomDiagramBlock keeps additional commas in role", () => {
  const data = customDiagram.parseCustomDiagramBlock("radial-team\nAlice, Architect, Platform");

  assert.deepEqual(data.members, [{ name: "Alice", role: "Architect, Platform" }]);
});

test("parseCustomDiagramBlock skips invalid member lines", () => {
  const data = customDiagram.parseCustomDiagramBlock("radial-team\nAlice\n, Missing name\nBob, Delivery");

  assert.deepEqual(data.members, [{ name: "Bob", role: "Delivery" }]);
});

test("renderSvg emits radial team classes and escaped text", () => {
  const svg = customDiagram.renderSvg({
    type: "radial-team",
    members: [
      { name: "Alice & Bob", role: "Architecture <Lead>" },
      { name: "Carol", role: "Delivery" },
    ],
  });

  assert.match(svg, /class="custom-diagram custom-diagram-radial-team"/);
  assert.match(svg, /custom-diagram-connector/);
  assert.match(svg, /custom-diagram-member-color-1/);
  assert.match(svg, /custom-diagram-member-color-2/);
  assert.match(svg, /Alice &amp; Bob/);
  assert.match(svg, /Architecture &lt;Lead&gt;/);
});

test("renderSvg emits unknown diagram fallback", () => {
  const svg = customDiagram.renderSvg({ type: "bad<type>", members: [] });

  assert.match(svg, /custom-diagram-unknown/);
  assert.match(svg, /bad&lt;type&gt;/);
});

test("radialTeamLayout wraps palette classes after six members", () => {
  const members = Array.from({ length: 7 }, (_, index) => ({ name: `M${index}`, role: "Role" }));
  const layout = customDiagram.radialTeamLayout(members);

  assert.equal(layout.members.length, 7);
  assert.equal(layout.members.some((member) => member.colorIndex === 1), true);
  assert.equal(layout.members.some((member) => member.colorIndex === 6), true);
});

test("markdown-it plugin renders only custom-diagram fences", () => {
  const md = {
    renderer: {
      rules: {
        fence: (_tokens, idx) => `default-${idx}`,
      },
    },
  };

  customDiagram(md);

  const custom = md.renderer.rules.fence(
    [{ info: "custom-diagram", content: "radial-team\nAlice, Architect" }],
    0,
    {},
    {},
    {},
  );
  const other = md.renderer.rules.fence([{ info: "js", content: "const x = 1;" }], 0, {}, {}, {});

  assert.match(custom, /custom-diagram-radial-team/);
  assert.equal(other, "default-0");
});
