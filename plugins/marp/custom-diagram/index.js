"use strict";

const radialDiagram = require("./radial-diagram.js");

function parseCustomDiagramBlock(content) {
  const relevantLines = String(content || "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  const type = relevantLines.shift() || "";
  const parsed = parseDiagram(type, relevantLines);
  return {
    type,
    ...parsed,
  };
}

function renderSvg(data) {
  if (data.type === radialDiagram.type) return radialDiagram.render(data);

  return renderUnknownSvg(data.type);
}

function renderUnknownSvg(type) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 480 96" class="custom-diagram custom-diagram-unknown"><text x="24" y="54">Unsupported custom diagram: ${escapeXml(type)}</text></svg>`;
}

function parseDiagram(type, lines) {
  if (type === radialTeam.type) return radialTeam.parse(lines);

  return {};
}

function escapeXml(text) {
  return String(text || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;");
}

function customDiagramMarkdownItPlugin(md) {
  const defaultFence =
    md.renderer.rules.fence ||
    ((tokens, idx, options, _env, slf) => slf.renderToken(tokens, idx, options));

  md.renderer.rules.fence = (tokens, idx, options, env, slf) => {
    const token = tokens[idx];
    const info = (token.info || "").trim();
    if (info === "custom-diagram") {
      return renderSvg(parseCustomDiagramBlock(token.content || ""));
    }
    return defaultFence(tokens, idx, options, env, slf);
  };
}

customDiagramMarkdownItPlugin.parseCustomDiagramBlock = parseCustomDiagramBlock;
customDiagramMarkdownItPlugin.renderSvg = renderSvg;
customDiagramMarkdownItPlugin.radialDiagramLayout = radialDiagram.radialDiagramLayout;
customDiagramMarkdownItPlugin.connectorGeometry = radialDiagram.connectorGeometry;

module.exports = customDiagramMarkdownItPlugin;
