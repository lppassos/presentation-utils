"use strict";

const TYPE = "radial";

function parse(lines) {
  const titleLine = lines[0] || "";
  const titleMatch = titleLine.match(/^title\s+(.+)$/i);
  const memberLines = titleMatch ? lines.slice(1) : lines;

  return {
    title: titleMatch ? titleMatch[1].trim() : "Team",
    members: memberLines
      .map((line) => {
        const commaIndex = line.indexOf(",");
        if (commaIndex === -1) return null;

        const name = line.slice(0, commaIndex).trim();
        const role = line.slice(commaIndex + 1).trim();
        if (!name || !role) return null;

        return { name, role };
      })
      .filter(Boolean),
  };
}

function render(data) {
  return renderRadialDiagramSvg(data.title || "Team", data.members || []);
}

function renderRadialDiagramSvg(title, members) {
  const layout = radialTeamLayout(members);
  const lines = [];
  lines.push(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${layout.width}" height="${layout.height}" viewBox="0 0 ${layout.width} ${layout.height}" class="custom-diagram custom-diagram-radial-team">`,
  );
  lines.push(
    `  <rect x="0" y="0" width="${layout.width}" height="${layout.height}" class="custom-diagram-background"/>`,
  );
  lines.push(...renderCenter(layout, title));

  for (const member of layout.members) {
    const connector = connectorGeometry(
      member.connectorStartX,
      member.connectorStartY,
      member.connectorEndX,
      member.connectorEndY,
    );
    lines.push(
      `  <circle cx="${connector.startCircleX}" cy="${connector.startCircleY}" r="${connector.radius}" class="custom-diagram-connector-dot"/>`,
    );
    lines.push(
      `  <circle cx="${connector.endCircleX}" cy="${connector.endCircleY}" r="${connector.radius}" class="custom-diagram-connector-dot"/>`,
    );
    lines.push(
      `  <path d="${connector.path}" fill="none" class="custom-diagram-connector"/>`,
    );
  }

  for (const member of layout.members) {
    lines.push(`  <g class="custom-diagram-member">`);
    lines.push(
      `    <rect x="${member.x}" y="${member.y}" width="${layout.memberWidth}" height="${layout.memberHeight}" rx="22" class="custom-diagram-member-fill custom-diagram-member-stroke"/>`,
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

function renderCenter(layout, title) {
  const middleX = layout.centerX + layout.centerWidth / 2;
  const outerWidth = layout.centerWidth / 2 - 80;

  return [
    `  <rect x="${layout.centerX}" y="${layout.centerY}" width="${layout.centerWidth}" height="${layout.centerHeight}" rx="${layout.centerHeight / 2}" class="custom-diagram-center custom-diagram-center-fill"/>`,
    `  <path d="M ${middleX + 45} ${layout.centerY - 10} h ${outerWidth} a ${layout.centerHeight / 2} ${layout.centerHeight / 2} 0 0 1 0 ${layout.centerHeight + 20} h -${outerWidth}" fill="none" class="custom-diagram-center-border"/>`,
    `  <path d="M ${middleX - 45} ${layout.centerY - 10} h -${outerWidth} a ${layout.centerHeight / 2} ${layout.centerHeight / 2} 0 0 0 0 ${layout.centerHeight + 20} h ${outerWidth}" fill="none" class="custom-diagram-center-border"/>`,
    `  <text x="${layout.centerX + layout.centerWidth / 2}" y="${layout.centerY + 41}" text-anchor="middle" font-size="24" font-weight="700" class="custom-diagram-center-label">${escapeXml(title)}</text>`,
  ];
}

function radialDiagramLayout(members) {
  const minWidth = 820;
  const centerWidth = 260;
  const centerHeight = 66;
  const memberWidth = 190;
  const memberHeight = 66;
  const columnGap = 24;
  const centerGap = 52;
  const centerConnectorSpan = 90;
  const padding = 24;
  const topCount = Math.ceil(members.length / 2);
  const bottomCount = members.length - topCount;
  const maxRowCount = Math.max(topCount, bottomCount, 1);
  const rowWidth = maxRowCount * memberWidth + (maxRowCount - 1) * columnGap;
  const width = Math.max(minWidth, rowWidth + padding * 2);
  const height = 420;
  const centerX = (width - centerWidth) / 2;
  const centerY = (height - centerHeight) / 2;
  const topY = centerY - centerGap - memberHeight;
  const bottomY = centerY + centerHeight + centerGap;

  const topMembers = members.slice(0, topCount).map((member) => member);
  const bottomMembers = members.slice(topCount).map((member) => member);

  const placed = [];
  const rows = [
    [topMembers, topY, centerY - 5, true],
    [bottomMembers, bottomY, centerY + centerHeight + 5, false],
  ];

  for (const [rowMembers, y, centerAnchorY, isTopRow] of rows) {
    const currentRowWidth = rowMembers.length === 0 ? 0 : rowMembers.length * memberWidth + (rowMembers.length - 1) * columnGap;
    const startX = (width - currentRowWidth) / 2;
    rowMembers.forEach((member, index) => {
      const x = startX + index * (memberWidth + columnGap);
      placed.push({
        x,
        y,
        connectorStartX: x + memberWidth / 2,
        connectorStartY: isTopRow ? y + memberHeight + 5 : y - 5,
        connectorEndX: centerConnectorX(centerX, centerWidth, centerConnectorSpan, rowMembers.length, index),
        connectorEndY: centerAnchorY,
        name: member.name,
        role: member.role,
      });
    });
  }

  placed.sort((a, b) => a.y - b.y || a.x - b.x);
  return { width, height, centerX, centerY, centerWidth, centerHeight, memberWidth, memberHeight, members: placed };
}

function centerConnectorX(centerX, centerWidth, span, count, index) {
  if (count <= 1) return centerX + centerWidth / 2;

  const startX = centerX + (centerWidth - span) / 2;
  return startX + (span * (index + 1)) / (count + 1);
}

function connectorGeometry(startX, startY, endX, endY) {
  const radius = 5;
  const midY = (startY + endY) / 2;
  const startCircleY = startY + Math.sign(midY - startY || endY - startY || 1) * radius;
  const endCircleY = endY + Math.sign(midY - endY || startY - endY || -1) * radius;

  if (startX === endX) {
    return {
      path: `M ${startX} ${startCircleY} L ${endX} ${endCircleY}`,
      startCircleX: startX,
      startCircleY,
      endCircleX: endX,
      endCircleY,
      radius,
    };
  }

  const path = roundedOrthogonalPath(
    [
      [startX, startCircleY],
      [startX, midY],
      [endX, midY],
      [endX, endCircleY],
    ],
    8,
  );
  return {
    path,
    startCircleX: startX,
    startCircleY,
    endCircleX: endX,
    endCircleY,
    radius,
  };
}

function roundedOrthogonalPath(points, cornerRadius) {
  let path = `M ${points[0][0]} ${points[0][1]}`;

  for (let index = 1; index < points.length - 1; index += 1) {
    const previous = points[index - 1];
    const current = points[index];
    const next = points[index + 1];
    const incomingLength = distance(previous, current);
    const outgoingLength = distance(current, next);
    const trim = Math.min(cornerRadius, incomingLength / 2, outgoingLength / 2);
    const cornerStart = moveToward(current, previous, trim);
    const cornerEnd = moveToward(current, next, trim);
    path += ` L ${cornerStart[0]} ${cornerStart[1]} Q ${current[0]} ${current[1]} ${cornerEnd[0]} ${cornerEnd[1]}`;
  }

  const last = points[points.length - 1];
  path += ` L ${last[0]} ${last[1]}`;
  return path;
}

function moveToward(from, to, distanceAmount) {
  const totalDistance = distance(from, to);
  if (totalDistance === 0) return [from[0], from[1]];

  const ratio = distanceAmount / totalDistance;
  return [from[0] + (to[0] - from[0]) * ratio, from[1] + (to[1] - from[1]) * ratio];
}

function distance(pointA, pointB) {
  return Math.abs(pointA[0] - pointB[0]) + Math.abs(pointA[1] - pointB[1]);
}

function escapeXml(text) {
  return String(text || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;");
}

module.exports = {
  type: TYPE,
  parse,
  render,
  renderRadialDiagramSvg,
  radialDiagramLayout,
  connectorGeometry,
};
