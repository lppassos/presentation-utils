# presentations-utils (Docker)

This image contains all the utilities to create documents and presentations from
markdown source files, using `asciidoctor` and `marp`.

## Build

```bash
docker build -t presentation-utils .
```

Optional: pin draw.io desktop version at build time:

```bash
docker build -t presentation-utils --build-arg DRAWIO_VERSION=24.7.17 .
```

## Usage

Mount your working directory to `/work`.

If you use PDF themes, mount your themes directory to `/themes/asciidoctor` (the container reads `/themes/asciidoctor/default-theme` if present).

If you use Marp themes, mount your themes directory to `/themes/marp` (the container reads `/themes/marp/default-theme` if present).

Notes:
- On Windows, prefer running these commands from PowerShell (path handling is simpler).
- If you run from Git Bash/MSYS2, add `MSYS_NO_PATHCONV=1` and pass file paths relative to `/work`.

Show available commands:

```bash
docker run --rm presentation-utils
```

### Convert AsciiDoc/Markdown to PDF

PowerShell:

```bash
docker run --rm \
  -v "${PWD}:/work" \
  -v "${HOME}/Documents/asciidoctor_styles:/themes/asciidoctor:ro" \
  presentation-utils convertto-pdf documento.adoc --theme mytheme-2025
```

Markdown input auto-converts to `.adoc` first:

```bash
docker run --rm -v "${PWD}:/work" presentation-utils convertto-pdf documento.md
```

Pass extra asciidoctor args after `--`:

```bash
docker run --rm -v "${PWD}:/work" \
  presentation-utils convertto-pdf documento.adoc -- --failure-level=WARN
```

Optimize/linearize (creates `*-out.pdf`):

```bash
docker run --rm -v "${PWD}:/work" presentation-utils convertto-pdf documento.adoc --optimize
```

#### Mermaid configuration from a PDF theme

To apply one Mermaid CLI (`mmdc`) JSON configuration to every `[mermaid]` block,
declare its path in the PDF theme. The path is resolved relative to the theme YAML
file, not to the source document:

```yaml
# /themes/asciidoctor/acme.yml
mermaid:
  config: mermaid/acme.json
```

An explicit document `mermaid-config` attribute still takes precedence over the
theme setting.

See [Asciidoctor Mermaid themes](docs/asciidoctor-mermaid.md) for the complete
configuration format and precedence rules.

### Convert Markdown to AsciiDoc

```bash
docker run --rm -v "${PWD}:/work" presentation-utils convertto-asciidoc documento.md
```

### Convert draw.io to PNG

```bash
docker run --rm -v "${PWD}:/work" presentation-utils convertto-png diagrama.drawio
```

### Convert Marp Markdown to PDF/HTML

Bundled Marp CLI + Chromium. Themes live in `/themes/marp`.

PowerShell:

```bash
docker run --rm \
  -v "${PWD}:/work" \
  -v "${HOME}/Documents/marp_styles:/themes/marp:ro" \
  presentation-utils convertto-presentation deck.md --format pdf
```

HTML:

```bash
docker run --rm -v "${PWD}:/work" presentation-utils convertto-marp deck.md --format html
```

Pass extra marp args after `--`:

```bash
docker run --rm -v "${PWD}:/work" presentation-utils convertto-presentation deck.md -- --bespoke.progress
```

## Git Bash / MSYS2

## Windows Path Notes

- Windows absolute paths (e.g. `C:\repo\file.md`) only work when the file is under the current directory mounted to `/work`.
- Passing an absolute path outside the current working directory will fail with "outside the current working directory".
- `convertto-presentation --theme` accepts a theme name/filename only (e.g. `--theme acme` or `--theme acme.css`), not a path.

When running from Git Bash on Windows, disable path conversion:

```bash
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/work" presentation-utils convertto-pdf documento.adoc
```
