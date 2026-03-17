# Last Page Marker (Asciidoctor PDF)

This repository includes a bundled Asciidoctor PDF extension that can place a theme-configured image marker at the end of a document.

The plugin is loaded by `bin/convertto-pdf`.

## Theme keys

The plugin activates only when `last-page-marker-image` is set in the PDF theme.

- `last-page-marker-image` (required)
  - Plain path example: `last-page-marker-image: end-marker.png`
  - Image macro example (lets you set size/fit): `last-page-marker-image: "image:end-marker.png[width=140,fit=contain]"`
- `last-page-marker-position` (optional)
  - Values: `bottom` or `inline`
  - Default: `bottom`
- `last-page-marker-alignment` (optional)
  - Values: `left`, `center`, `right`
  - Default: `center`

## Position behavior

- `bottom`
  - The marker is rendered inside the bottom page margin band of the last *content* page.
  - The image is scaled to fit within that margin band.
  - If the bottom margin is `0`, the marker is skipped.
- `inline`
  - The marker is inserted as a normal image block appended to the end of the document.

## Example theme snippet

Add these keys to your theme YAML (e.g., `themes/asciidoctor/my-theme.yml`):

```yml
last-page-marker-image: "image:end-marker.png[width=140,fit=contain]"
last-page-marker-position: bottom
last-page-marker-alignment: center
```

## Example AsciiDoc

```adoc
= Example Document
:doctype: article

This is a multi-page document.

<<<

More content on the last page.
```

## Notes

- Image paths in `last-page-marker-image` are resolved relative to the active `pdf-themesdir`.
- Use a sufficiently large bottom margin (e.g., `page.margin: [20mm, 20mm, 30mm, 20mm]`) if you want the marker to be visible when `position=bottom`.
