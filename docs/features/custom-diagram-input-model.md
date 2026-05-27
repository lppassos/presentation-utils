# Custom Diagram Input Model

Custom diagrams use one generic block or fence named `custom-diagram`. The block body is parsed the same way by Asciidoctor PDF and Marp plugins.

## Block Forms

Asciidoctor:

```asciidoc
[custom-diagram, target=team.svg]
----
radial-team
Alice, Architecture
Bob, Delivery
----
```

Marp Markdown:

````markdown
```custom-diagram
radial-team
Alice, Architecture
Bob, Delivery
```
````

## Parsing Rules

- Split the block content into lines.
- Trim each line.
- Ignore empty or whitespace-only lines.
- Treat the first remaining line as the diagram type.
- Treat all following relevant lines as diagram-specific entries.
- Skip invalid diagram-specific entries rather than failing the whole document render.

## `radial-team` Entries

Each `radial-team` entry is parsed as:

```text
name, role
```

- `name` is the member display name.
- `role` is the member role or responsibility text.
- Both values must be present after trimming.
- Additional commas are treated as part of the role text.
