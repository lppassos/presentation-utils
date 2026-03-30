# Gantt Chart: Work Completion Indicator

## Description

As a presentation author, I want to specify and visualize task completion in Gantt charts, so that viewers can quickly understand progress status directly on the timeline.

## Acceptance Criteria

1. Create a Gantt definition that contains:
   - `period: <value>`
   - an `activities:` section
   - (optionally) a `completion:` section after `activities:`
2. When the `completion:` section is omitted, render the Gantt chart exactly as before (no completion indicators).
3. When the `completion:` section is present, parse each completion entry as:
   - `<taskId>, <value>` where `<value>` is either:
     - a percentage when it ends with `%` (e.g., `80%`), or
     - an absolute value otherwise (e.g., `3`), in the same unit as `duration`.
4. For any task that has no corresponding entry in `completion:`, treat its completion as `0`.
5. Allow completion entries to reference:
   - leaf tasks (tasks with a `duration=`), and
   - group tasks (tasks that contain nested activities).
   - Note: group completion is **independent** from child task completion values.
6. For each task bar rendered in the diagram:
   - render a thin completion line centered vertically inside the bar, at the completion point from the start of the bar.
   - if completion is specified as a percentage, position the line at `duration * (percentage / 100)`.
   - if completion is specified as an absolute value, position the line at that absolute offset from the bar start.
7. Clamp completion to the bar range:
   - values below `0` render at the bar start
   - values beyond the task duration render at the bar end
8. Only render completion lines when a bar is rendered:
   - leaf task bars always render completion lines (when `completion:` is present).
   - group task completion lines render **only if** a group bar is rendered (i.e., not when `group-bars: none`).
   - completion entries that target milestones are ignored.
9. Use the completion line color from the active theme.
   - Asciidoctor: read document attribute `gantt-completion-color`, defaulting to `#ff0000`.
   - Marp: render the completion line with CSS class `gantt-completion-color`, with default color `#ff0000` when no CSS overrides are provided.
10. Implement the same behavior in both rendering paths:
   - the Asciidoctor plugin (`plugins/asciidoctor/gantt-diagram`)
   - the Marp plugin (`plugins/marp/gantt-diagram`)
11. Verify the following example renders completion lines for task `1` and task `2.1`, and uses `0` completion for all other tasks:

```yaml
period: week
activities:
    1, "Work", duration=15
    2, "Project Management"
        2.1, "Project Management", duration=15
completion:
    1, 80%
    2.1, 3
```

## Additional Information

- Parsing
  - `completion:` is a new top-level section that appears after `activities:`.
  - Completion values can be percent (suffix `%`) or absolute (numeric).
  - If `completion:` exists but a task is missing, completion defaults to `0`.
- Rendering
  - The completion indicator is a thin line in the middle of the bar.
  - The line uses a theme-provided color, defaulting to `#ff0000`.
  - Group completion is rendered only when a group bar is rendered.
  - Milestones ignore completion entries.
- Theming
  - Asciidoctor: `gantt-completion-color`.
  - Marp: CSS class `gantt-completion-color`.
- Relevant components (per `docs/PROJECT_STRUCTURE.md`)
  - Asciidoctor extension: `plugins/asciidoctor/gantt-diagram/extension.rb`
  - Marp markdown-it plugin: `plugins/marp/gantt-diagram/index.js`
