"use strict";

function parseCustomDiagramBlock(content) {
  const relevantLines = String(content || "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  const type = relevantLines.shift() || "";
  return {
    type,
    members: type === "radial-team" ? parseRadialTeamMembers(relevantLines) : [],
  };
}

function parseRadialTeamMembers(lines) {
  return lines
    .map((line) => {
      const commaIndex = line.indexOf(",");
      if (commaIndex === -1) return null;

      const name = line.slice(0, commaIndex).trim();
      const role = line.slice(commaIndex + 1).trim();
      if (!name || !role) return null;

      return { name, role };
    })
    .filter(Boolean);
}

function renderSvg(data) {
  if (data.type === "radial-team") return renderRadialTeamSvg(data.members || []);

  return renderUnknownSvg(data.type);
}

function renderRadialTeamSvg(members) {
  const layout = radialTeamLayout(members);
  const lines = [];
  lines.push(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${layout.width} ${layout.height}" class="custom-diagram custom-diagram-radial-team">`,
  );
  lines.push(
    `  <rect x="0" y="0" width="${layout.width}" height="${layout.height}" class="custom-diagram-background"/>`,
  );
  lines.push(
    `  <rect x="${layout.centerX}" y="${layout.centerY}" width="${layout.centerWidth}" height="${layout.centerHeight}" rx="32" class="custom-diagram-center"/>`,
  );
  lines.push(
    `  <text x="${layout.centerX + layout.centerWidth / 2}" y="${layout.centerY + 52}" text-anchor="middle" font-size="24" font-weight="700" class="custom-diagram-center-label">Team</text>`,
  );

  for (const member of layout.members) {
    lines.push(
      `  <line x1="${member.connectorStartX}" y1="${member.connectorY}" x2="${member.connectorEndX}" y2="${member.connectorY}" class="custom-diagram-connector"/>`,
    );
  }

  for (const member of layout.members) {
    lines.push(
      `  <g class="custom-diagram-member custom-diagram-member-color-${member.colorIndex}">`,
    );
    lines.push(
      `    <rect x="${member.x}" y="${member.y}" width="${layout.memberWidth}" height="${layout.memberHeight}" rx="22" class="custom-diagram-member-fill"/>`,
    );
    lines.push(
      `    <text x="${member.x + layout.memberWidth / 2}" y="${member.y + 28}" text-anchor="middle" font-size="16" font-weight="700" class="custom-diagram-member-name">${escapeXml(member.name)}</text>`,
    );
    lines.push(
      `    <text x="${member.x + layout.memberWidth / 2}" y="${member.y + 48}" text-anchor="middle" font-size="12" class="custom-diagram-member-role">${escapeXml(member.role)}</text>`,
    );
    lines.push("  </g>");
  }

  lines.push("</svg>");
  return lines.join("\n");
}

function renderUnknownSvg(type) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 480 96" class="custom-diagram custom-diagram-unknown"><text x="24" y="54">Unsupported custom diagram: ${escapeXml(type)}</text></svg>`;
}

function radialTeamLayout(members) {
  const width = 820;
  const centerWidth = 260;
  const centerHeight = 86;
  const memberWidth = 190;
  const memberHeight = 66;
  const rowGap = 24;
  const padding = 24;
  const sideCount = Math.max(Math.ceil(members.length / 2), Math.floor(members.length / 2));
  const sideHeight = sideCount === 0 ? memberHeight : sideCount * memberHeight + (sideCount - 1) * rowGap;
  const height = Math.max(420, sideHeight + padding * 2);
  const centerX = (width - centerWidth) / 2;
  const centerY = (height - centerHeight) / 2;

  const leftMembers = [];
  const rightMembers = [];
  members.forEach((member, index) => {
    (index % 2 === 0 ? leftMembers : rightMembers).push([member, index]);
  });

  const placed = [];
  const columns = [
    [leftMembers, padding, centerX, "left"],
    [rightMembers, width - padding - memberWidth, centerX + centerWidth, "right"],
  ];

  for (const [columnMembers, x, centerEdgeX, side] of columns) {
    const columnHeight = columnMembers.length === 0 ? 0 : columnMembers.length * memberHeight + (columnMembers.length - 1) * rowGap;
    const startY = (height - columnHeight) / 2;
    columnMembers.forEach(([member, originalIndex], index) => {
      const y = startY + index * (memberHeight + rowGap);
      placed.push({
        x,
        y,
        connectorY: y + memberHeight / 2,
        connectorStartX: side === "left" ? x + memberWidth : x,
        connectorEndX: centerEdgeX,
        name: member.name,
        role: member.role,
        colorIndex: (originalIndex % 6) + 1,
      });
    });
  }

  placed.sort((a, b) => a.y - b.y || a.x - b.x);
  return { width, height, centerX, centerY, centerWidth, centerHeight, memberWidth, memberHeight, members: placed };
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
customDiagramMarkdownItPlugin.radialTeamLayout = radialTeamLayout;

module.exports = customDiagramMarkdownItPlugin;
