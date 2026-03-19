# Gantt diagram plugin

In asciidoctor documents I want to have a plugin that generates a diagram image for a block called gantt.

In the asciidoctor file we will have the following information.

Example:

```
```
[gantt, target=gantt_diagram.png]
----
period: "week"
activities:
  1, "Planning"
    2, "Analysis", duration=3, dependencies=1
    3, "Requirements", duration=2, dependencies=2
  4, "Delivery"
    5, "Development", duration=6, dependencies=4
    6, "Tests", duration=2, dependencies=5
  7, "Launch", dependencies=6
  8, "Support", duration=12, dependencies=7
----
```
```

This will produce a gantt diagram where time is shown in weeks, in this case with 23 weeks. Consider the following mockup as an example of what should be rendered in the png to include in the pdf document rendering.

```
Activity           | W1 | W2 | W3 | W4 | .. | .. | W10 | W11 | W12 | W13 | .. | .. | W23
-------------------+---------------------------------------------------------------------
1. Planning        |
  2. Analysis      | [============]
  3. Requirements  |              [========]
-------------------+---------------------------------------------------------------------
4. Delivery        |
  5. Development   |              [====================]
  6. Tests         |                                   [========]
-------------------+---------------------------------------------------------------------
7. Launch          |                                   <> 
8. Support         |                                            [=======================]
```

Indented activities are treated as part of the group defined by the previous non-indented row. Group rows do not require a duration. Tasks without a duration and no subtasks are milestones and render as a diamond.

When a group contains more than one descendant task (including milestones), the group row renders a thinner summary bar spanning from the earliest descendant start to the latest descendant end. The summary bar fill and its end markers use `gantt-marker-color`.

The tasks will be aligned according to the dependencies.

The colors and fonts to use will be picked up from the theme.
