"use strict";

function parseDependencyToken(raw) {
  const token = String(raw || "").trim();
  if (!token) return null;

  const match = token.match(/^(ss|ff)(.+)$/i);
  if (match) {
    const id = String(match[2] || "").trim();
    if (!id) return null;
    return { type: match[1].toUpperCase(), id };
  }

  return { type: "FS", id: token };
}

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
  const groupDescendants = buildGroupDescendants(activities);
  const computed = computeSchedule(activities, groupDescendants);
  const totalUnits = Math.max(0, ...computed.map((activity) => activity.end || 0));
  const columns = Math.max(1, Math.ceil(totalUnits));

  return { period, activities: computed, totalUnits, columns, groupBars };
}

function buildGroupDescendants(activities) {
  const groupDescendants = {};

  activities.forEach((activity, index) => {
    if (!activity.isGroup) return;

    const groupLevel = activity.indentLevel;
    const leafDescendants = [];

    for (
      let j = index + 1;
      j < activities.length && activities[j].indentLevel > groupLevel;
      j += 1
    ) {
      if (!activities[j].isGroup) leafDescendants.push(activities[j].id);
    }

    groupDescendants[activity.id] = leafDescendants;
  });

  return groupDescendants;
}

function parseActivity(line) {
  const match = line.match(/^([^\s,]+)\s*,\s*"([^"]+)"(?:\s*,\s*(.+))?$/);
  if (!match) return null;

  const id = match[1];
  const label = match[2].trim();
  const extras = (match[3] || "").split(",").map((item) => item.trim());

  let duration = null;
  let dependencies = [];
  let dependencyTokens = [];
  let notBeforeSlot = null;

  for (const extra of extras) {
    if (/^duration\s*=\s*([0-9]*\.?[0-9]+)$/.test(extra)) {
      const value = parseFloat(RegExp.$1);
      if (Number.isFinite(value)) duration = value;
    } else if (/^dependencies\s*=\s*(.+)$/.test(extra)) {
      dependencies = RegExp.$1
        .split(/[\s,;]+/)
        .map((dep) => dep.trim())
        .filter(Boolean);
      dependencyTokens = dependencies.map(parseDependencyToken).filter(Boolean);
    } else if (/^notBefore\s*=\s*([0-9]*\.?[0-9]+)$/.test(extra)) {
      const value = parseFloat(RegExp.$1);
      if (Number.isFinite(value)) notBeforeSlot = Math.max(1, value);
    }
  }

  return { id, label, duration, dependencies, dependencyTokens, notBeforeSlot };
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

function computeSchedule(activities, groupDescendants) {
  const resolved = {};
  const pending = activities.map((activity) => ({ ...activity }));
  const maxPasses = pending.length * 2;

  for (let pass = 0; pass < maxPasses; pass += 1) {
    let progressed = false;

    // Resolve group summary ranges once all leaf descendants are resolved.
    for (let i = pending.length - 1; i >= 0; i -= 1) {
      const activity = pending[i];
      if (!activity.isGroup) continue;

      const leafIds = (groupDescendants && groupDescendants[activity.id]) || [];
      if (leafIds.length === 0) {
        activity.start = 0;
        activity.end = 0;
        activity.duration = 0;
        resolved[activity.id] = activity;
        pending.splice(i, 1);
        progressed = true;
        continue;
      }

      if (!leafIds.every((id) => resolved[id])) continue;

      const starts = leafIds.map((id) => resolved[id].start);
      const ends = leafIds.map((id) => resolved[id].end);
      activity.start = Math.min(...starts);
      activity.end = Math.max(...ends);
      activity.duration = Math.max(0, activity.end - activity.start);
      resolved[activity.id] = activity;
      pending.splice(i, 1);
      progressed = true;
    }

    for (let i = pending.length - 1; i >= 0; i -= 1) {
      const activity = pending[i];
      if (activity.isGroup) continue;

      const deps = (activity.dependencyTokens || []).filter(Boolean);

      const referenced = deps
        .map((dep) => dep && dep.id)
        .filter((id) => id !== undefined && id !== null);
      const resolvedReferenced = referenced.filter((id) => resolved[id]);
      if (resolvedReferenced.length !== referenced.length) continue;

      const notBeforeStartAt = activity.notBeforeSlot
        ? Math.max(0, Number(activity.notBeforeSlot) - 1)
        : 0;

      const fsEnds = deps
        .filter((dep) => dep.type === "FS")
        .map((dep) => resolved[dep.id].end);
      const ssStarts = deps
        .filter((dep) => dep.type === "SS")
        .map((dep) => resolved[dep.id].start);
      const ffEnds = deps
        .filter((dep) => dep.type === "FF")
        .map((dep) => resolved[dep.id].end);

      const startMin = Math.max(
        notBeforeStartAt,
        fsEnds.length ? Math.max(...fsEnds) : 0,
        ssStarts.length ? Math.max(...ssStarts) : 0,
      );
      const endMin = ffEnds.length ? Math.max(...ffEnds) : 0;

      const hasSS = ssStarts.length > 0;
      const hasFF = ffEnds.length > 0;

      const d = activity.isMilestone ? 0 : activity.duration || 0;

      if (hasSS && hasFF) {
        activity.start = startMin;
        activity.end = Math.max(endMin, activity.start);
        activity.duration = Math.max(0, activity.end - activity.start);
      } else if (hasFF) {
        activity.start = Math.max(startMin, endMin - d);
        activity.end = activity.start + d;
      } else {
        activity.start = startMin;
        activity.end = activity.start + d;
      }

      resolved[activity.id] = activity;
      pending.splice(i, 1);
      progressed = true;
    }

    if (!progressed) break;
  }

  for (const activity of pending) {
    if (activity.isGroup || activity.isMilestone) {
      const notBeforeStartAt = activity.notBeforeSlot
        ? Math.max(0, Number(activity.notBeforeSlot) - 1)
        : 0;
      activity.start = notBeforeStartAt;
      activity.end = notBeforeStartAt;
    } else {
      const notBeforeStartAt = activity.notBeforeSlot
        ? Math.max(0, Number(activity.notBeforeSlot) - 1)
        : 0;
      activity.start = notBeforeStartAt;
      activity.end = notBeforeStartAt + (activity.duration || 0);
    }
    resolved[activity.id] = activity;
  }

  let ordered = activities.map((activity) => resolved[activity.id] || activity);

  // Render-only flags: compute whether a group has >1 leaf descendant.
  ordered.forEach((activity) => {
    if (!activity.isGroup) return;
    const leafIds = (groupDescendants && groupDescendants[activity.id]) || [];
    activity.hasGroupBar = leafIds.length > 1;
  });

  return ordered;
}

function renderSvg(activities, totalUnits, columns, period, groupBars, options) {
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
  const normalizedColumns = Math.max(columns || 1, 1);
  const periodLabel = (() => {
    const key = String(period || "").toLowerCase();
    if (key === "week") return "W";
    if (key === "day") return "D";
    if (key === "month") return "M";
    return String(period || "")[0]?.toUpperCase() || "U";
  })();

  const periodCellPadding = 6;
  const maxPeriodLabelLength =
    periodLabel.length + String(normalizedColumns).length;
  const minCellWidth = Math.floor(
    maxPeriodLabelLength * (fontSize * 0.7) + periodCellPadding * 2,
  );
  cellWidth = Math.max(cellWidth, minCellWidth);

  const gridWidth = (normalizedColumns + 1) * cellWidth;
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

  for (let idx = 0; idx < normalizedColumns; idx += 1) {
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

  for (let idx = 1; idx <= normalizedColumns; idx += 1) {
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
  const { period, activities, totalUnits, columns, groupBars } = parseGanttBlock(content);
  const svg = renderSvg(activities, totalUnits, columns, period, groupBars, opts || {});
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
