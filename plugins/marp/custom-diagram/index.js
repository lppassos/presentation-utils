"use strict";

const radialDiagram = require("./radial-diagram.js");

const CUSTOM_DIAGRAM_INFO_RE = /^custom-diagram(?:\s+\[([^\]]*)\])?$/;

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

function parseFenceInfo(info) {
  const match = String(info || "").trim().match(CUSTOM_DIAGRAM_INFO_RE);
  if (!match) return null;

  const wrapperClasses = String(match[1] || "")
    .split(/\s+/)
    .map((name) => name.trim())
    .filter(Boolean);

  return {
    wrapperClasses,
  };
}

function renderDiagramHtml(data, options = {}) {
  const svg = renderSvg(data);
  const wrapperClasses = Array.isArray(options.wrapperClasses)
    ? options.wrapperClasses.filter(Boolean)
    : [];

  if (wrapperClasses.length === 0) return svg;

  return `<div class="${escapeXml(wrapperClasses.join(" "))}">${svg}</div>`;
}

function parseDiagram(type, lines) {
  if (type === radialDiagram.type) return radialDiagram.parse(lines);

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
    ((tokens, idx, options, _env, slf) =>
      slf.renderToken(tokens, idx, options));

  md.renderer.rules.fence = (tokens, idx, options, env, slf) => {
    const token = tokens[idx];
    const parsedInfo = parseFenceInfo(token.info);
    if (parsedInfo) {
      return renderDiagramHtml(parseCustomDiagramBlock(token.content || ""), parsedInfo);
    }
    return defaultFence(tokens, idx, options, env, slf);
  };
}

customDiagramMarkdownItPlugin.parseCustomDiagramBlock = parseCustomDiagramBlock;
customDiagramMarkdownItPlugin.parseFenceInfo = parseFenceInfo;
customDiagramMarkdownItPlugin.renderDiagramHtml = renderDiagramHtml;
customDiagramMarkdownItPlugin.renderSvg = renderSvg;
customDiagramMarkdownItPlugin.radialDiagramLayout =
  radialDiagram.radialDiagramLayout;
customDiagramMarkdownItPlugin.connectorGeometry =
  radialDiagram.connectorGeometry;

module.exports = customDiagramMarkdownItPlugin;
