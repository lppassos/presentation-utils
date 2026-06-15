# Asciidoctor chart theme

This document describes the theme-driven settings for the Asciidoctor PDF `chart` block extension.

## Block syntax

Charts are declared with a `[chart]` block whose body is a YAML document.

Inline CSV example:

```adoc
[chart, target=sales-trend.svg]
----
type: line
title: Monthly Sales
x_axis_title: Month
y_axis_title: Revenue
legend: right
data: |
  month,actual,forecast
  Jan,12,10
  Feb,18,16
  Mar,15,18
  Apr,22,20
----
```

External CSV example:

```adoc
[chart, target=sales-breakdown.svg]
----
type: column
title: Sales Breakdown
x_axis_title: Quarter
y_axis_title: Revenue
legend: bottom
data_file: ./data/sales-breakdown.csv
----
```

## Supported configuration keys

- `type`: `line`, `bar`, or `column`
- `title`
- `x_axis_title`
- `y_axis_title`
- `series`: optional ordered list of series column names
- `override_series`: optional list of objects used to override series metadata (`name`, optional `title`, optional `type`, and `axis` set to `primary` or `secondary`; `primary` is the default and `secondary` is supported for `line`, `area`, and `column`)
- `secondary_axis`: optional object for the secondary numeric axis
- `secondary_axis.title`: optional title for the secondary numeric axis
- `secondary_axis.format`: `#` for raw numeric labels or `%` to multiply tick values by `100` and append `%`
- `legend`: `none`, `left`, `right`, `bottom`, `top-left`, or `top-right`
- `category_axis_padding`: `true` or `false`; when `true`, the first and last category positions are inset from the left and right plot edges
- `data`: inline CSV in a YAML literal block
- `data_file`: path to a CSV file relative to the source document

## Theme attributes

The chart extension reads document attributes first and theme keys second.

- `chart-diagram-background-color`
- `chart-diagram-font-family`
- `chart-diagram-font-size`
- `chart-diagram-title-font-size`
- `chart-diagram-axis-title-font-size`
- `chart-diagram-tick-font-size`
- `chart-diagram-text-color`
- `chart-diagram-title-color`
- `chart-diagram-axis-color`
- `chart-diagram-grid-color`
- `chart-diagram-legend-text-color`
- `chart-diagram-legend-border-color`
- `chart-diagram-legend-background-color`
- `chart-diagram-series-palette`

The default Asciidoctor theme exposes matching keys under the `chart-diagram` namespace.

## Notes

- The first CSV column is treated as the category axis.
- Every remaining rendered column is treated as a numeric series.
- When `override_series` marks one or more series with `axis: secondary`, those series are scaled against the opposite-side numeric axis while the remaining series continue to use the primary axis.
- On `line`, `area`, and `column` charts, `override_series.type` can switch an individual series between `line`, `area`, and `column` to create mixed charts.
- The output artifact is an SVG that is embedded in the generated PDF.
