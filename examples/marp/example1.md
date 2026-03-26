---
marp: true
theme: default
paginate: true
---

# Gantt Diagram Example

This slide deck demonstrates the `gantt` block plugin for Marp.

---

# Delivery Plan

```gantt
period: "week"
group-bars: all
activities:
  1, "Planning"
    2, "Analysis", duration=3
    3, "Requirements", duration=2, dependencies=2
  4, "Delivery"
    5, "Development", duration=6, dependencies=3
    6, "Tests"
      6.1, "My real test", duration=2, dependencies=5
  7, "Launch", dependencies=6
  8, "Support", duration=12
  9, "Training", duration=2, dependencies=6, notBefore=10
```

---

## Notes

- The diagram is generated as an SVG next to this file.
- Use `convertto-presentation` to render PDF or HTML.
