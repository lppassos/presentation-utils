# Radial Team Geometry

The `radial-team` renderer uses deterministic SVG geometry so Asciidoctor PDF and Marp output match structurally.

## Canvas

- Minimum canvas width: `820`.
- Minimum canvas height: `420`.
- Outer padding: `24`.
- Center node width: `260`.
- Center node height: `86`.
- Member cell width: `190`.
- Member cell height: `66`.
- Member cell corner radius: `22`.
- Connector stroke width: `2`.

The canvas height expands when more than six members are rendered. Each side of the diagram receives half of the members, and the side with the most members determines the required height.

## Placement

- The center node is horizontally and vertically centered.
- Members are split into two columns around the center node.
- Even-indexed members are placed in the left column.
- Odd-indexed members are placed in the right column.
- Members in each column are vertically distributed with a consistent row gap of `24`.
- Left column cells align near the left padding.
- Right column cells align near the right padding.
- Connectors run from the inner edge of each member cell to the corresponding side of the center node.

## Text

- The center node displays `Team`.
- Each member cell displays the parsed member name on the first line.
- Each member cell displays the parsed member role on the second line.
- Text is centered inside each cell.

## Color Assignment

- Member cells receive palette entries by member order.
- Palette assignment wraps when there are more members than configured colors.
- Marp renders palette classes in the form `custom-diagram-member-color-N`.
- Asciidoctor resolves the same ordered palette from document attributes or PDF theme settings.
