# Asciidoctor theme

This document describes how Asciidoctor PDF themes are provided and used in this repository, including the default theme and the theme-driven attributes for bundled extensions.

## Theme location and defaults

- Theme directory: `themes/asciidoctor/`
- Default theme file: `themes/asciidoctor/default-theme.yml`
- Default theme pointer: `themes/asciidoctor/default-theme` (contains the theme name)

When converting to PDF, the container looks for `/themes/asciidoctor/default-theme` and uses the name in that file. If you mount your own themes directory, keep the same structure and provide a `default-theme` file pointing to the desired theme name.

## Using a custom theme

Mount your themes directory to `/themes/asciidoctor` and select a theme name:

```bash
docker run --rm \
  -v "${PWD}:/work" \
  -v "${HOME}/Documents/asciidoctor_styles:/themes/asciidoctor:ro" \
  presentation-utils convertto-pdf documento.adoc --theme mytheme-2025
```

If you do not pass `--theme`, the default theme is selected using the `default-theme` file inside the themes directory.

## Default theme content

The default theme is defined in `themes/asciidoctor/default-theme.yml`. It sets base typography, headings, code styling, blockquote styling, admonition icons, table colors, and footer rules. Use it as a starting point for customizations.

## Extension theme attributes

Some extensions read colors and typography from document attributes so they can be themed consistently.

### Gantt diagram

The Gantt diagram extension reads the following attributes (with defaults):

- `gantt-font-family` (defaults to `base-font-family`)
- `gantt-font-size` (default `12`)
- `gantt-cell-width` (default `28`)
- `gantt-row-height` (default `26`)
- `gantt-header-height` (default `28`)
- `gantt-text-color` (default `#222222`)
- `gantt-grid-color` (default `#d8d8d8`)
- `gantt-bar-color` (default `#4b8bbf`)
- `gantt-marker-color` (default `#000000`)
- `gantt-header-bg` (default `#f5f5f5`)

Group rows with more than one descendant task render a thinner summary bar spanning the earliest descendant start to the latest descendant end. The summary bar fill and end markers use `gantt-marker-color`.

You can set these in your AsciiDoc header:

```adoc
:gantt-font-family: Noto Sans
:gantt-font-size: 11
:gantt-grid-color: #e2e6ea
:gantt-marker-color: #111111
```
