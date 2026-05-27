# Custom Diagram Plugin

Custom diagrams are rendered from blocks named `custom-diagram`. The first non-empty line selects the diagram type. Empty and whitespace-only lines are ignored.

The first supported diagram type is `radial-team`.

## Asciidoctor PDF

```asciidoc
[custom-diagram, target=team.svg]
----
radial-team
Alice, Architecture
Bob, Delivery
Carol, Quality
Dave, Operations
----
```

The Asciidoctor PDF plugin writes an SVG to `imagesoutdir` and embeds it as an image in the generated PDF.

## Marp

````markdown
```custom-diagram
radial-team
Alice, Architecture
Bob, Delivery
Carol, Quality
Dave, Operations
```
````

The Marp plugin renders inline SVG. Colors and typography are provided by CSS classes in the active Marp theme.

## `radial-team` Lines

Each member line uses this format:

```text
name, role
```

- `name` is shown as the primary cell text.
- `role` is shown as the secondary cell text.
- Both values are required.
- Additional commas are kept in the role text.
- Invalid member lines are skipped.

## Asciidoctor Theme Settings

The Asciidoctor renderer reads document attributes first and PDF theme keys second. The default theme includes these keys:

```yaml
custom-diagram:
  background-color: #ffffff
  font-family: Noto Sans
  center-font-size: 24
  member-name-font-size: 16
  member-role-font-size: 12
  center-fill: #eef4f8
  center-stroke: #6f8798
  center-text-color: #263743
  connector-color: #8aa0af
  member-stroke: #6f8798
  member-text-color: #ffffff
  member-role-color: #ffffff
  member-palette: #7890a1,#8aa0af,#6f8798,#9badba,#607888,#a5b5bf
```

Equivalent document attributes use the `custom-diagram-` prefix, for example `custom-diagram-center-fill`.

## Marp Theme Classes

The Marp SVG is scoped under `.custom-diagram` and uses semantic classes including:

- `.custom-diagram-radial-team`
- `.custom-diagram-background`
- `.custom-diagram-connector`
- `.custom-diagram-center-fill`
- `.custom-diagram-center-label`
- `.custom-diagram-member`
- `.custom-diagram-member-fill`
- `.custom-diagram-member-stroke`
- `.custom-diagram-member-name`
- `.custom-diagram-member-role`
- `.custom-diagram-member-color-1` through `.custom-diagram-member-color-6`
