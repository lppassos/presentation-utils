# Gantt Diagram in MARP

I want to include a plugin in my marp cli call, that reacts to a block included in the presentation markdown file and generates the gantt chart model.

Example of the input we will have in our presentation.md:

```

```gantt
period: "week"
activities:
  1, "Planning"
    2, "Analysis", duration=3, dependencies=1
    2.1, "Kickoff", duration=1, dependencies=SS2
    3, "Requirements", duration=2, dependencies=2
  4, "Delivery"
    5, "Development", duration=6, dependencies=4
    6, "Tests", duration=2, dependencies=5
  7, "Launch", dependencies=6
  8, "Support", duration=12, dependencies=7
  9, "Training", duration=1.5, dependencies=6, notBefore=10
  10, "Wrap-up Window", duration=1, dependencies=SS6 FF8
```
```

Dependencies can reference either task ids or group ids. When a dependency targets a group id, the dependency resolves to the group's summary range computed from its leaf descendants (start=min leaf start, end=max leaf end):

- `FS<id>` (or bare `<id>`): constrains the dependent start to be >= dependency end
- `SS<id>`: constrains the dependent start to be >= dependency start
- `FF<id>`: constrains the dependent end to be >= dependency end


This will produce a gantt diagram where time is shown in weeks, in this case with 23 weeks. Consider the following mockup as an example of what should be rendered in the png to include in the pdf document rendering.

For the rendering of the svg consider the ruby code that is present in `plugins/asciidoctor/gantt-diagram/extension.rb`.

The plugin source code will be stored in `plugins/marp/gantt-diagram`.

This code will be added to the Dockerfile container and convertto-presentation must include it when calling marp to render the presentation either in pdf or html.
