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
- `marp-preprocess.mjs`: Pre-processing pipeline for Marp presentations. Runs all registered preprocessor modules (e.g. `drawio-image`) on the input markdown before `marp` is invoked, writes the result to a temp file next to the original (so relative paths remain valid), and prints the temp file path to stdout. New preprocessors can be added by dropping a module into `plugins/marp/` and registering it here.

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
- `plugins/marp/`: Marp markdown-it plugins and pre-processor modules loaded by the conversion pipeline.
  - `plugins/marp/gantt-diagram/`: markdown-it fence plugin that renders `gantt` code blocks as inline SVG Gantt charts.
  - `plugins/marp/drawio-image/`: Pre-processor module (used by `marp-preprocess.mjs`) that detects standard Markdown image references with a `.drawio` extension, exports each diagram to a transparent PNG under `.imggen/` via headless draw.io (`xvfb-run drawio --transparent`), and rewrites the image src to the generated PNG. Conversion is skipped when an up-to-date PNG already exists.
