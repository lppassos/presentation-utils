"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");

const customDiagram = require("./index.js");

test("parseCustomDiagramBlock ignores whitespace and detects radial-team", () => {
  const data = customDiagram.parseCustomDiagramBlock("\n  radial-team  \n\n Alice, Architect \n");

  assert.equal(data.type, "radial-team");
  assert.equal(data.title, "Team");
  assert.deepEqual(data.members, [{ name: "Alice", role: "Architect" }]);
});

test("parseCustomDiagramBlock reads radial-team title from first line", () => {
  const data = customDiagram.parseCustomDiagramBlock("radial-team\ntitle Platform Team\nAlice, Architect");

  assert.equal(data.title, "Platform Team");
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
    title: "Platform Team",
    members: [
      { name: "Alice & Bob", role: "Architecture <Lead>" },
      { name: "Carol", role: "Delivery" },
    ],
  });

  assert.match(svg, /class="custom-diagram custom-diagram-radial-team"/);
  assert.match(svg, /custom-diagram-connector/);
  assert.match(svg, /custom-diagram-connector-dot/);
  assert.match(svg, /custom-diagram-center-border/);
  assert.match(svg, /<g class="custom-diagram-member">/);
  assert.match(svg, /<path d="M [^"]+" fill="none" class="custom-diagram-connector"\/>/);
  assert.match(svg, /Platform Team/);
  assert.match(svg, /Alice &amp; Bob/);
  assert.match(svg, /Architecture &lt;Lead&gt;/);
});

test("renderSvg emits unknown diagram fallback", () => {
  const svg = customDiagram.renderSvg({ type: "bad<type>", members: [] });

  assert.match(svg, /custom-diagram-unknown/);
  assert.match(svg, /bad&lt;type&gt;/);
});

test("radialTeamLayout keeps all members without palette metadata", () => {
  const members = Array.from({ length: 7 }, (_, index) => ({ name: `M${index}`, role: "Role" }));
  const layout = customDiagram.radialTeamLayout(members);

  assert.equal(layout.members.length, 7);
  assert.equal(layout.members.some((member) => Object.hasOwn(member, "colorIndex")), false);
});

test("radialTeamLayout places members in top and bottom rows with centered connector anchors", () => {
  const layout = customDiagram.radialTeamLayout([
    { name: "A", role: "R" },
    { name: "B", role: "R" },
    { name: "C", role: "R" },
    { name: "D", role: "R" },
  ]);

  const topRow = layout.members.filter((member) => member.y < layout.centerY);
  const bottomRow = layout.members.filter((member) => member.y > layout.centerY);

  assert.equal(topRow.length, 2);
  assert.equal(bottomRow.length, 2);
  assert.deepEqual(
    topRow.map((member) => [member.connectorStartY, member.connectorEndY, member.connectorEndX]),
    [
      [topRow[0].y + layout.memberHeight + 5, layout.centerY - 5, layout.centerX + 115],
      [topRow[1].y + layout.memberHeight + 5, layout.centerY - 5, layout.centerX + 145],
    ],
  );
  assert.deepEqual(
    bottomRow.map((member) => [member.connectorStartY, member.connectorEndY, member.connectorEndX]),
    [
      [bottomRow[0].y - 5, layout.centerY + layout.centerHeight + 5, layout.centerX + 115],
      [bottomRow[1].y - 5, layout.centerY + layout.centerHeight + 5, layout.centerX + 145],
    ],
  );
});

test("connectorGeometry uses rounded elbows and offsets circles inside anchors", () => {
  const elbow = customDiagram.connectorGeometry(10, 20, 50, 100);
  const straight = customDiagram.connectorGeometry(10, 20, 10, 100);

  assert.equal(elbow.startCircleY, 25);
  assert.equal(elbow.endCircleY, 95);
  assert.match(elbow.path, /^M 10 25 L 10 52 Q 10 60 18 60 L 42 60 Q 50 60 50 68 L 50 95$/);
  assert.equal(straight.startCircleY, 25);
  assert.equal(straight.endCircleY, 95);
  assert.equal(straight.path, "M 10 25 L 10 95");
});

test("renderSvg matches Asciidoctor radial structure with classes", () => {
  const svg = customDiagram.renderSvg({
    type: "radial-team",
    title: "Platform Team",
    members: [
      { name: "Alice & Bob", role: "Architecture <Lead>" },
      { name: "Carol", role: "Delivery" },
    ],
  });

  assert.equal(
    svg,
    [
      '<svg xmlns="http://www.w3.org/2000/svg" width="820" height="420" viewBox="0 0 820 420" class="custom-diagram custom-diagram-radial-team">',
      '  <rect x="0" y="0" width="820" height="420" class="custom-diagram-background"/>',
      '  <rect x="280" y="177" width="260" height="66" rx="33" class="custom-diagram-center custom-diagram-center-fill"/>',
      '  <path d="M 455 167 h 50 a 33 33 0 0 1 0 86 h -50" fill="none" class="custom-diagram-center-border"/>',
      '  <path d="M 365 167 h -50 a 33 33 0 0 0 0 86 h 50" fill="none" class="custom-diagram-center-border"/>',
      '  <text x="410" y="218" text-anchor="middle" font-size="24" font-weight="700" class="custom-diagram-center-label">Platform Team</text>',
      '  <circle cx="410" cy="135" r="5" class="custom-diagram-connector-dot"/>',
      '  <circle cx="410" cy="167" r="5" class="custom-diagram-connector-dot"/>',
      '  <path d="M 410 135 L 410 167" fill="none" class="custom-diagram-connector"/>',
      '  <circle cx="410" cy="285" r="5" class="custom-diagram-connector-dot"/>',
      '  <circle cx="410" cy="253" r="5" class="custom-diagram-connector-dot"/>',
      '  <path d="M 410 285 L 410 253" fill="none" class="custom-diagram-connector"/>',
      '  <g class="custom-diagram-member">',
      '    <rect x="315" y="59" width="190" height="66" rx="22" class="custom-diagram-member-fill custom-diagram-member-stroke"/>',
      '    <text x="410" y="87" text-anchor="middle" font-size="16" font-weight="700" class="custom-diagram-member-name">Alice &amp; Bob</text>',
      '    <text x="410" y="107" text-anchor="middle" font-size="12" class="custom-diagram-member-role">Architecture &lt;Lead&gt;</text>',
      '  </g>',
      '  <g class="custom-diagram-member">',
      '    <rect x="315" y="295" width="190" height="66" rx="22" class="custom-diagram-member-fill custom-diagram-member-stroke"/>',
      '    <text x="410" y="323" text-anchor="middle" font-size="16" font-weight="700" class="custom-diagram-member-name">Carol</text>',
      '    <text x="410" y="343" text-anchor="middle" font-size="12" class="custom-diagram-member-role">Delivery</text>',
      '  </g>',
      '</svg>',
    ].join("\n"),
  );
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
