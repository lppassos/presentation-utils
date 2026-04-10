# Project Structure

This document describes the layout of the `presentation-utils` repository and the purpose of each directory and key file.

## Top-Level

- `bin/`: CLI entrypoints and conversion helpers used inside the container image.
- `docs/`: Documentation files for the project.
- `plugins/`: Custom Asciidoctor extensions bundled in the container.
- `themes/`: Default example themes to use in Asciidoctor and Marp
- `Dockerfile`: Builds the Debian-based image with Asciidoctor, Marp, draw.io, and supporting tools.
- `README.md`: Usage instructions, examples, and platform notes.
- `presentation-utils.ps1`: PowerShell helper script (Windows-friendly utilities).

## bin/

- `presentations-utils`: Main entrypoint that lists available commands and dispatches to subcommands.
- `convertto-asciidoc`: Converts Markdown to AsciiDoc using `kramdoc`.
- `convertto-pdf`: Converts AsciiDoc/Markdown to PDF via Asciidoctor PDF, optional theme and optimization.
- `convertto-png`: Converts draw.io diagrams to PNG using headless draw.io.
- `convertto-presentation`: Converts Marp Markdown to PDF or HTML with theme embedding.
- `marp-theme-embed.js`: Inlines @import rules and embeds local assets into Marp theme CSS.

## themes/

- themes/asciidoctor: Asciidoctor PDF example themes copied into the container
- themes/asciidoctor/default-theme.yml: Asciidoctor PDF theme that is the default
- themes/asciidoctor/default-theme: Reference to the default theme to use in the conversion
- `themes/marp/`: Marp themes copied into `/themes/marp` inside the container.
- `themes/marp/default.css`: Default Marp theme stylesheet.
- `themes/marp/default-theme`: Text file indicating the default Marp theme name.

## docs/

- `docs/PROJECT_STRUCTURE.md`: This file.

## plugins/

- `plugins/asciidoctor/`: Asciidoctor extensions loaded by conversion scripts.
  - `plugins/asciidoctor/advanced-title-page/`: PDF converter override that renders a customisable title page layout.
  - `plugins/asciidoctor/gantt-diagram/`: Block processor and PDF converter override that renders Gantt charts as SVG images.
  - `plugins/asciidoctor/last-page-marker/`: PDF converter override that stamps a configurable marker image on the last page.
  - `plugins/asciidoctor/drawio-image/`: TreeProcessor extension that detects image references with a `.drawio` extension, exports them to PNG via headless draw.io (`xvfb-run drawio`), and rewrites the image target to the generated PNG before the PDF converter runs. Conversion is skipped when an up-to-date PNG already exists.
