"use strict";

function parseGanttBlock(content) {
  const lines = content.split(/\r?\n/);
  let period = "week";
  let inActivities = false;
  let groupBars = "all";
  const rawEntries = [];

  for (const line of lines) {
    const stripped = line.trim();
    if (!stripped) continue;

    if (stripped.startsWith("period:")) {
      const value = stripped.split(":", 2)[1] || "";
      period = value.trim().replace(/^"|"$/g, "");
      continue;
    }

    if (stripped.startsWith("group-bars:")) {
      const value = stripped.split(":", 2)[1] || "";
      groupBars = value;
      continue;
    }

    if (stripped.startsWith("activities:")) {
      inActivities = true;
      continue;
    }

    if (!inActivities) continue;

    const indent = (line.match(/^[\t ]*/) || [""])[0].replace(
      /\t/g,
      "  ",
    ).length;
    const activity = parseActivity(stripped);
    if (activity) rawEntries.push({ indent, activity });
  }

  const activities = applyGrouping(rawEntries);
  const computed = computeSchedule(activities);
  const totalUnits = Math.max(
    0,
    ...computed.map((activity) => activity.end || 0),
  );

  return { period, activities: computed, totalUnits, groupBars };
}

function parseActivity(line) {
  const match = line.match(/^([^\s,]+)\s*,\s*"([^"]+)"(?:\s*,\s*(.+))?$/);
  if (!match) return null;

  const id = match[1];
  const label = match[2].trim();
  const extras = (match[3] || "").split(",").map((item) => item.trim());

  let duration = null;
  let dependencies = [];

  for (const extra of extras) {
    if (/^duration\s*=\s*(\d+)$/.test(extra)) {
      duration = parseInt(RegExp.$1, 10);
    } else if (/^dependencies\s*=\s*(.+)$/.test(extra)) {
      dependencies = RegExp.$1.split(/[\s,;]+/).map((dep) => dep.trim());
    }
  }

  return { id, label, duration, dependencies };
}

function applyGrouping(entries) {
  const grouped = [];
  let current_group_level = 0;
  let indent_levels = [];
  let baseIndent = 0;

  entries.forEach((entry, index) => {
    const activity = entry.activity;
    if (!activity) return;

    const indentLevel = Number(entry.indent || 0);
    if (baseIndent === 0) baseIndent = indentLevel;

    if (indentLevel > baseIndent) {
      current_group_level = current_group_level + 1;
      indent_levels.push(baseIndent);
      baseIndent = indentLevel;
    } else {
      while (indentLevel < baseIndent && current_group_level > 0) {
        current_group_level = current_group_level - 1;
        baseIndent = indent_levels.pop();
      }
    }
    activity.indentLevel = current_group_level;
    activity.isGroup = false;
    activity.isMilestone =
      activity.duration === null || activity.duration === undefined;
    grouped.push(activity);

    const nextEntry = entries[index + 1];
    if (nextEntry && Number(nextEntry.indent || 0) > indentLevel) {
      activity.isGroup = true;
      activity.isMilestone = false;
    }
  });

  return grouped;
}

function computeSchedule(activities) {
  const resolved = {};
  const pending = activities.map((activity) => ({ ...activity }));
  const maxPasses = pending.length * 2;

  for (let pass = 0; pass < maxPasses; pass += 1) {
    let progressed = false;

    for (let i = pending.length - 1; i >= 0; i -= 1) {
      const activity = pending[i];
      if (activity.isGroup) continue;

      const deps = activity.dependencies || [];
      const depsEnds = deps
        .map((dep) => resolved[dep] && resolved[dep].end)
        .filter((value) => value !== undefined && value !== null);

      if (depsEnds.length !== deps.length) continue;

      const startAt = depsEnds.length ? Math.max(...depsEnds) : 0;
      activity.start = startAt;
      const duration = activity.isMilestone ? 0 : activity.duration || 0;
      activity.end = startAt + duration;
      resolved[activity.id] = activity;
      pending.splice(i, 1);
      progressed = true;
    }

    if (!progressed) break;
  }

  for (const activity of pending) {
    if (activity.isGroup || activity.isMilestone) {
      activity.start = 0;
      activity.end = 0;
    } else {
      activity.start = 0;
      activity.end = activity.duration || 0;
    }
    resolved[activity.id] = activity;
  }

  let ordered = activities.map((activity) => resolved[activity.id] || activity);

  ordered.forEach((activity, index) => {
    if (!activity.isGroup) {
      return;
    }

    let groupLevel = activity.indentLevel;
    let descendants = [];
    for (
      let j = index + 1;
      j < ordered.length && ordered[j].indentLevel > groupLevel;
      j++
    ) {
      if (!ordered[j].isGroup) {
        descendants.push(ordered[j]);
      }
    }

    console.error(JSON.stringify([activity, descendants]));
    if (descendants.length >= 1) {
      let groupStart = 999999;
      let groupEnd = 0;
      descendants.forEach((a) => {
        if (groupStart > a.start) groupStart = a.start;
        if (groupEnd < a.end) groupEnd = a.end;
      });
      activity.start = groupStart;
      activity.end = groupEnd;
      activity.duration = groupEnd - groupStart;
      activity.hasGroupBar = descendants.length > 1;
    } else {
      activity.start = 0;
      activity.end = 0;
      activity.duration = 0;
      activity.hasGroupBar = false;
    }
  });

  return ordered;
}

function renderSvg(activities, totalUnits, period, groupBars, options) {
  const fontSize = options.fontSize || 12;
  let cellWidth = options.cellWidth || 28;
  const rowHeight = options.rowHeight || 26;
  const headerHeight = options.headerHeight || 28;
  const gridColor = options.gridColor || "#d8d8d8";

  const labelTexts = activities.map(
    (activity) => `${activity.id}. ${activity.label}`,
  );
  const labelMax = labelTexts.reduce(
    (max, text) => Math.max(max, text.length),
    10,
  );
  const labelColWidth = Math.max(
    160,
    Math.floor(labelMax * (fontSize * 0.6) + 24),
  );

  const leftPadding = 12;
  const topPadding = 12;
  const rightPadding = 12;
  const bottomPadding = 12;

  const normalizedTotal = Math.max(totalUnits, 1);
  const periodLabel = (() => {
    const key = String(period || "").toLowerCase();
    if (key === "week") return "W";
    if (key === "day") return "D";
    if (key === "month") return "M";
    return String(period || "")[0]?.toUpperCase() || "U";
  })();

  const periodCellPadding = 6;
  const maxPeriodLabelLength =
    periodLabel.length + String(normalizedTotal).length;
  const minCellWidth = Math.floor(
    maxPeriodLabelLength * (fontSize * 0.7) + periodCellPadding * 2,
  );
  cellWidth = Math.max(cellWidth, minCellWidth);

  const gridWidth = (normalizedTotal + 1) * cellWidth;
  const width = leftPadding + labelColWidth + gridWidth + rightPadding;

  const indentWidth = 14;
  const separatorHeight = 10;
  const rows = buildRows(activities, rowHeight, separatorHeight);
  const rowsHeight = rows.reduce((sum, row) => sum + row.height, 0);
  const height = topPadding + headerHeight + rowsHeight + bottomPadding;

  const barHeight = Math.floor(rowHeight * 0.55);

  const svgLines = [];
  svgLines.push(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" class="gantt-diagram">`,
  );
  svgLines.push(
    `  <rect x="0" y="0" width="${width}" height="${height}" class="background"/>`,
  );
  svgLines.push(
    `  <rect x="${leftPadding}" y="${topPadding}" width="${labelColWidth + gridWidth}" height="${headerHeight}" class="header"/>`,
  );

  const headerY =
    topPadding + Math.floor(headerHeight / 2) + Math.floor(fontSize / 2) - 2;
  svgLines.push(
    `  <text x="${leftPadding + 4}" y="${headerY}" font-size="${fontSize}" font-weight="700" class="header">Activity</text>`,
  );

  for (let idx = 0; idx < normalizedTotal; idx += 1) {
    const label = `${periodLabel}${idx + 1}`;
    const x = leftPadding + labelColWidth + idx * cellWidth + cellWidth;
    svgLines.push(
      `  <text x="${x}" y="${headerY}" text-anchor="middle" font-size="${fontSize}" font-weight="700" class="header">${escapeXml(label)}</text>`,
    );
  }

  const gridTop = topPadding + headerHeight;
  const gridBottom = height - bottomPadding;
  svgLines.push(
    `  <line x1="${leftPadding + labelColWidth}" y1="${topPadding}" x2="${leftPadding + labelColWidth}" y2="${gridBottom}" stroke="${gridColor}"/>`,
  );

  for (let idx = 1; idx <= normalizedTotal; idx += 1) {
    if (idx % 5 !== 0) continue;
    const x =
      leftPadding + labelColWidth + idx * cellWidth + Math.floor(cellWidth / 2);
    svgLines.push(
      `  <line x1="${x}" y1="${topPadding}" x2="${x}" y2="${gridBottom}" stroke="${gridColor}"/>`,
    );
  }

  let currentY = gridTop;
  rows.forEach((row, _index) => {
    const rowY = currentY;
    currentY += row.height;

    if (row.type === "separator") {
      const lineY = rowY + row.height / 2;
      svgLines.push(
        `  <line x1="${leftPadding}" y1="${lineY}" x2="${leftPadding + labelColWidth + gridWidth}" y2="${lineY}" stroke="${gridColor}"/>`,
      );
      return;
    }

    const activity = row.activity;
    const label = `${activity.id}. ${activity.label}`;
    const labelX = leftPadding + 4 + activity.indentLevel * indentWidth;
    const textY = rowY + row.height / 2 + Math.floor(fontSize / 2) - 2;
    const fontWeight = activity.isGroup ? "bold" : "normal";
    svgLines.push(
      `  <text x="${labelX}" y="${textY}" font-size="${fontSize}" font-weight="${fontWeight}" class="activity-label">${escapeXml(label)}</text>`,
    );

    const barY = rowY + Math.floor((row.height - barHeight) / 2);
    const startX =
      leftPadding +
      labelColWidth +
      activity.start * cellWidth +
      Math.floor(cellWidth / 2);

    if (activity.isGroup) {
      if (
        (activity.hasGroupBar && groupBars !== "none") ||
        groupBars === "all"
      ) {
        const groupBarHeight = Math.max(2, Math.floor(barHeight / 2));
        const width = activity.duration * cellWidth;
        groupBar(svgLines, startX, barY, width, groupBarHeight);
      }
      return;
    }

    if (activity.isMilestone) {
      const milestoneX =
        leftPadding +
        labelColWidth +
        activity.start * cellWidth +
        Math.floor(cellWidth / 2);
      milestoneMarker(svgLines, milestoneX, barY, barHeight);
      return;
    }

    const widthValue = activity.duration * cellWidth;
    taskBar(svgLines, startX, barY, widthValue, barHeight);
  });

  svgLines.push("</svg>");
  return svgLines.join("\n");
}

function escapeXml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;");
}

function buildRows(activities, rowHeight, separatorHeight) {
  const rows = [];
  let currentGroup = null;

  activities.forEach((activity, index) => {
    rows.push({ type: "activity", activity, height: rowHeight });

    if (activity.isGroup) {
      currentGroup = activity;
      return;
    }

    const nextActivity = activities[index + 1];
    if (currentGroup && (!nextActivity || nextActivity.indentLevel === 0)) {
      rows.push({ type: "separator", height: separatorHeight });
      currentGroup = null;
    }
  });

  return rows;
}

function groupBar(svgLines, startX, barY, width, barHeight) {
  const markerWidth = Math.max(6, Math.floor(barHeight * 0.8));
  const markerHeight = Math.max(8, Math.floor(barHeight * 1.5));
  const markerTip = Math.max(3, Math.floor(markerHeight * 0.35));

  svgLines.push(
    `  <rect x="${startX}" y="${barY}" width="${width}" height="${barHeight}" class="group-bar"/>`,
  );
  svgLines.push(
    `  <polygon points="${markerPoints(startX, barY, markerWidth, markerHeight, markerTip)}" class="marker"/>`,
  );
  svgLines.push(
    `  <polygon points="${markerPoints(startX + width, barY, markerWidth, markerHeight, markerTip)}" class="marker"/>`,
  );
}

function taskBar(svgLines, startX, barY, width, barHeight) {
  const markerWidth = Math.max(6, Math.floor(barHeight * 0.8));
  const markerHeight = Math.max(8, Math.floor(barHeight * 0.9));
  const markerTip = Math.max(3, Math.floor(markerHeight * 0.35));

  svgLines.push(
    `  <rect x="${startX}" y="${barY}" width="${width}" height="${barHeight}" class="bar"/>`,
  );
  svgLines.push(
    `  <polygon points="${markerPoints(startX, barY, markerWidth, markerHeight, markerTip)}" class="marker"/>`,
  );
  svgLines.push(
    `  <polygon points="${markerPoints(startX + width, barY, markerWidth, markerHeight, markerTip)}" class="marker"/>`,
  );
}

function milestoneMarker(svgLines, milestoneX, barY, barHeight) {
  const barCenterY = barY + barHeight / 2;
  const markerWidth = Math.max(6, Math.floor(barHeight * 0.8));
  svgLines.push(
    `  <polygon points="${diamondPoints(milestoneX, barCenterY, markerWidth)}" class="marker"/>`,
  );
}

function markerPoints(centerX, topY, width, height, tipHeight) {
  const half = width / 2;
  const tipY = topY + height;
  const baseY = tipY - tipHeight;
  const leftX = centerX - half;
  const rightX = centerX + half;
  return `${leftX},${topY} ${rightX},${topY} ${rightX},${baseY} ${centerX},${tipY} ${leftX},${baseY}`;
}

function diamondPoints(centerX, centerY, width) {
  const half = width / 2;
  const leftX = centerX - half;
  const rightX = centerX + half;
  const topY = centerY - half;
  const bottomY = centerY + half;
  return `${centerX},${topY} ${rightX},${centerY} ${centerX},${bottomY} ${leftX},${centerY}`;
}

function generateSvg(content, _env, opts) {
  const { period, activities, totalUnits, groupBars } =
    parseGanttBlock(content);
  const svg = renderSvg(activities, totalUnits, period, groupBars, opts || {});
  return svg;
}

function ganttMarkdownItPlugin(md, pluginOptions) {
  const defaultFence =
    md.renderer.rules.fence ||
    ((tokens, idx, options, _env, slf) =>
      slf.renderToken(tokens, idx, options));

  md.renderer.rules.fence = (tokens, idx, options, env, slf) => {
    const token = tokens[idx];
    const info = (token.info || "").trim();
    if (info === "gantt") {
      return generateSvg(token.content || "", env || {}, pluginOptions || {});
    }
    return defaultFence(tokens, idx, options, env, slf);
  };
}

module.exports = ganttMarkdownItPlugin;
