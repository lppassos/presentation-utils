require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

require_relative 'extension'

class FakeChartDocument
  def initialize(attrs = {})
    @attrs = attrs
  end

  def attr(name, default = nil)
    @attrs.fetch(name.to_s, default)
  end
end

def chart_parser
  PresentationUtils::ChartDiagram::Parser.new
end

def chart_renderer
  PresentationUtils::ChartDiagram::Renderer.new
end

def chart_converter
  PresentationUtils::ChartDiagram::ChartBlockConverter.allocate
end

class TestChartParser < Minitest::Test
  def test_parses_inline_csv_chart
    document = FakeChartDocument.new('docdir' => Dir.pwd)
    data = chart_parser.parse(<<~YAML, document)
      type: line
      title: Monthly Sales
      legend: right
      data: |
        month,actual,forecast
        Jan,12,10
        Feb,18,16
    YAML

    assert_equal 'line', data['type']
    assert_equal 'Monthly Sales', data['title']
    assert_equal 'right', data['legend']
    assert_equal %w[Jan Feb], data['dataset']['categories']
    assert_equal(%w[actual forecast], data['dataset']['series'].map { |entry| entry['name'] })
    assert_equal [12.0, 18.0], data['dataset']['series'][0]['values']
  end

  def test_parses_external_csv_file_relative_to_docfile
    Dir.mktmpdir do |dir|
      data_dir = File.join(dir, 'data')
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, 'sales.csv'), "month,actual,forecast\nJan,12,10\nFeb,18,16\n")
      document = FakeChartDocument.new('docdir' => dir, 'docfile' => File.join(dir, 'chart.adoc'))

      data = chart_parser.parse(<<~YAML, document)
        type: column
        data_file: ./data/sales.csv
      YAML

      assert_equal 'column', data['type']
      assert_equal %w[Jan Feb], data['dataset']['categories']
      assert_equal [10.0, 16.0], data['dataset']['series'][1]['values']
    end
  end

  def test_defaults_legend_to_none
    document = FakeChartDocument.new('docdir' => Dir.pwd)
    data = chart_parser.parse(<<~YAML, document)
      type: line
      data: |
        month,actual
        Jan,12
    YAML

    assert_equal 'none', data['legend']
  end

  def test_parses_category_axis_padding_option
    document = FakeChartDocument.new('docdir' => Dir.pwd)
    data = chart_parser.parse(<<~YAML, document)
      type: line
      category_axis_padding: true
      data: |
        month,actual
        Jan,12
        Feb,18
    YAML

    assert_equal true, data['category_axis_padding']
  end

  def test_respects_explicit_series_order
    document = FakeChartDocument.new('docdir' => Dir.pwd)
    data = chart_parser.parse(<<~YAML, document)
      type: line
      series:
        - forecast
        - actual
      data: |
        month,actual,forecast,target
        Jan,12,10,11
        Feb,18,16,17
    YAML

    assert_equal(%w[forecast actual], data['dataset']['series'].map { |entry| entry['name'] })
    assert_equal [10.0, 16.0], data['dataset']['series'][0]['values']
  end

  def test_parses_override_series_configuration
    document = FakeChartDocument.new('docdir' => Dir.pwd)
    data = chart_parser.parse(<<~YAML, document)
      type: line
      secondary_axis:
        title: Variation
        format: "%"
      override_series:
        - name: variation
          title: Variation %
          axis: secondary
          type: column
      data: |
        month,actual,variation
        Jan,12,5
        Feb,18,12
    YAML

    assert_equal 'Variation', data['secondary_axis']['title']
    assert_equal '%', data['secondary_axis']['format']
    assert_equal(%w[primary secondary], data['dataset']['series'].map { |entry| entry['axis'] })
    assert_equal(['actual', 'Variation %'], data['dataset']['series'].map { |entry| entry['title'] })
    assert_equal([nil, 'column'], data['dataset']['series'].map { |entry| entry['type'] })
    assert_equal 5.0, data['dataset']['secondary_min_value']
    assert_equal 12.0, data['dataset']['secondary_max_value']
  end

  def test_defaults_secondary_axis_format_to_number
    document = FakeChartDocument.new('docdir' => Dir.pwd)
    data = chart_parser.parse(<<~YAML, document)
      type: line
      secondary_axis:
        title: Variation
      override_series:
        - name: variation
          axis: secondary
      data: |
        month,actual,variation
        Jan,12,0.05
        Feb,18,0.12
    YAML

    assert_equal '#', data['secondary_axis']['format']
  end

  def test_rejects_invalid_yaml
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse("type: [line\n", document)
    end

    assert_includes error.message, 'invalid chart YAML'
  end

  def test_rejects_unsupported_chart_type
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse("type: pie\ndata: |\n  month,actual\n  Jan,12\n", document)
    end

    assert_equal 'unsupported chart type: pie', error.message
  end

  def test_rejects_invalid_legend_value
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse("type: line\nlegend: center\ndata: |\n  month,actual\n  Jan,12\n", document)
    end

    assert_equal 'unsupported legend value: center', error.message
  end

  def test_rejects_duplicate_headers
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse("type: line\ndata: |\n  month,actual,actual\n  Jan,12,10\n", document)
    end

    assert_equal 'chart CSV headers must be unique', error.message
  end

  def test_rejects_non_numeric_series_values
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse("type: line\ndata: |\n  month,actual\n  Jan,abc\n", document)
    end

    assert_includes error.message, 'chart series values must be numeric'
  end

  def test_rejects_unknown_series_selection
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse(<<~YAML, document)
        type: line
        series:
          - target
        data: |
          month,actual,forecast
          Jan,12,10
      YAML
    end

    assert_equal 'unknown series column(s): target', error.message
  end

  def test_rejects_invalid_category_axis_padding
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse("type: line\ncategory_axis_padding: maybe\ndata: |\n  month,actual\n  Jan,12\n", document)
    end

    assert_equal 'category_axis_padding must be true or false', error.message
  end

  def test_rejects_unknown_override_series_selection
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse(<<~YAML, document)
        type: line
        override_series:
          - name: variation
            axis: secondary
        data: |
          month,actual,forecast
          Jan,12,10
      YAML
    end

    assert_equal 'unknown override series column(s): variation', error.message
  end

  def test_rejects_override_series_without_primary_series
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse(<<~YAML, document)
        type: line
        override_series:
          - name: actual
            axis: secondary
        series:
          - actual
        data: |
          month,actual
          Jan,12
      YAML
    end

    assert_equal 'override_series must leave at least one primary-axis series', error.message
  end

  def test_rejects_secondary_override_for_bar_charts
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse(<<~YAML, document)
        type: bar
        override_series:
          - name: actual
            axis: secondary
        data: |
          month,actual,forecast
          Jan,12,10
      YAML
    end

    assert_equal 'override_series with axis secondary is not supported for bar charts', error.message
  end

  def test_rejects_invalid_override_series_axis
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse(<<~YAML, document)
        type: line
        override_series:
          - name: actual
            axis: tertiary
        data: |
          month,actual
          Jan,12
      YAML
    end

    assert_equal 'unsupported override_series axis: tertiary', error.message
  end

  def test_rejects_invalid_override_series_type
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse(<<~YAML, document)
        type: line
        override_series:
          - name: actual
            type: scatter
        data: |
          month,actual
          Jan,12
      YAML
    end

    assert_equal 'unsupported override_series type: scatter', error.message
  end

  def test_rejects_bar_override_type_on_vertical_chart
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse(<<~YAML, document)
        type: line
        override_series:
          - name: actual
            type: bar
        data: |
          month,actual
          Jan,12
      YAML
    end

    assert_equal 'override_series type bar is only supported for bar charts', error.message
  end

  def test_rejects_duplicate_override_series_names
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse(<<~YAML, document)
        type: line
        override_series:
          - name: actual
          - name: actual
            title: Revenue
        data: |
          month,actual
          Jan,12
      YAML
    end

    assert_equal 'override_series names must be unique', error.message
  end

  def test_rejects_type_overrides_for_bar_charts
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse(<<~YAML, document)
        type: bar
        override_series:
          - name: actual
            type: line
        data: |
          month,actual
          Jan,12
      YAML
    end

    assert_equal 'override_series type overrides are not supported for bar charts', error.message
  end

  def test_rejects_invalid_secondary_axis_format
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse(<<~YAML, document)
        type: line
        secondary_axis:
          title: Variation
          format: currency
        data: |
          month,actual
          Jan,12
      YAML
    end

    assert_equal 'unsupported secondary_axis format: currency', error.message
  end

  def test_rejects_non_object_secondary_axis
    document = FakeChartDocument.new('docdir' => Dir.pwd)

    error = assert_raises(PresentationUtils::ChartDiagram::Error) do
      chart_parser.parse("type: line\nsecondary_axis: variation\ndata: |\n  month,actual\n  Jan,12\n", document)
    end

    assert_equal 'secondary_axis must be a YAML object', error.message
  end
end

class TestChartConverter < Minitest::Test
  def test_normalize_target_forces_svg_extension
    converter = chart_converter

    assert_equal 'chart.svg', converter.normalize_target('chart.png')
    assert_equal 'chart.svg', converter.normalize_target('chart')
  end

  def test_resolve_output_path_uses_imagesoutdir
    Dir.mktmpdir do |dir|
      converter = chart_converter
      document = FakeChartDocument.new('docdir' => dir, 'imagesoutdir' => '.imggen')

      assert_equal File.join(dir, '.imggen', 'chart.svg'), converter.resolve_output_path(document, 'chart.svg')
    end
  end
end

class TestChartRenderer < Minitest::Test
  def setup
    @document = FakeChartDocument.new(
      'base-font-family' => 'Test Sans',
      'chart-diagram-title-color' => '#112233',
      'chart-diagram-legend-background-color' => '#f8fafc'
    )
    @dataset = {
      'category_header' => 'month',
      'categories' => %w[Jan Feb Mar],
      'series' => [
        { 'name' => 'actual', 'values' => [12.0, 18.0, 15.0] },
        { 'name' => 'forecast', 'values' => [10.0, 16.0, 18.0] }
      ],
      'series_count' => 2,
      'row_count' => 3,
      'min_value' => 10.0,
      'max_value' => 18.0
    }
  end

  def test_renderer_uses_document_attribute_setting
    svg = chart_renderer.render(@document, {
                                  'type' => 'line',
                                  'title' => 'Monthly Sales',
                                  'legend' => 'none',
                                  'dataset' => @dataset
                                })

    assert_includes svg, 'fill="#112233"'
    assert_includes svg, 'font-family="Test Sans"'
  end

  def test_renders_line_chart_svg_with_path_and_points
    svg = chart_renderer.render(@document, {
                                  'type' => 'line',
                                  'title' => 'Monthly Sales',
                                  'x_axis_title' => 'Month',
                                  'y_axis_title' => 'Revenue',
                                  'legend' => 'top-right',
                                  'dataset' => @dataset
                                })

    assert_includes svg, '<path d="M '
    assert_includes svg, '<circle '
    assert_includes svg, '>Monthly Sales<'
    assert_includes svg, '>Revenue<'
    assert_includes svg, '>Month<'
    assert_includes svg, 'rx="10"'
    assert_includes svg, '>actual<'
    assert_includes svg, '>forecast<'
    assert_match(%r{<text x="[^"]+" y="28"[^>]*>Monthly Sales</text>}, svg)
  end

  def test_renders_column_chart_rectangles
    svg = chart_renderer.render(@document, {
                                  'type' => 'column',
                                  'legend' => 'right',
                                  'dataset' => @dataset
                                })

    assert_operator svg.scan('<rect ').length, :>=, 5
    assert_includes svg, '>Jan<'
    assert_includes svg, '>Mar<'
  end

  def test_renders_bar_chart_rectangles_and_category_labels
    svg = chart_renderer.render(@document, {
                                  'type' => 'bar',
                                  'legend' => 'left',
                                  'x_axis_title' => 'Revenue',
                                  'y_axis_title' => 'Month',
                                  'dataset' => @dataset
                                })

    assert_operator svg.scan('<rect ').length, :>=, 5
    assert_includes svg, '>Revenue<'
    assert_includes svg, '>Month<'
    assert_includes svg, '>Feb<'
    assert_includes svg,
                    '<text x="286" y="326" text-anchor="middle" font-family="Test Sans" font-size="11.0" fill="#1b1b1b">0</text>'
    assert_includes svg,
                    '<text x="826" y="326" text-anchor="middle" font-family="Test Sans" font-size="11.0" fill="#1b1b1b">20</text>'
    refute_includes svg,
                    '<text x="84" y="312" text-anchor="end" font-family="Test Sans" font-size="11.0" fill="#1b1b1b">0</text>'
  end

  def test_suppresses_legend_when_none
    svg = chart_renderer.render(@document, {
                                  'type' => 'line',
                                  'legend' => 'none',
                                  'dataset' => @dataset
                                })

    refute_includes svg, '>actual<'
    refute_includes svg, 'legend-background'
  end

  def test_renders_bottom_legend_outside_plot_area
    svg = chart_renderer.render(@document, {
                                  'type' => 'column',
                                  'legend' => 'bottom',
                                  'dataset' => @dataset
                                })

    assert_includes svg, 'rx="10"'
    assert_includes svg, '>actual<'
    assert_includes svg, '>forecast<'
    assert_includes svg, '<rect x="292" y="350" width="140" height="58" rx="10"'
  end

  def test_bottom_legend_sits_below_bottom_axis_title_with_padding
    svg = chart_renderer.render(@document, {
                                  'type' => 'column',
                                  'legend' => 'bottom',
                                  'x_axis_title' => 'Month',
                                  'dataset' => @dataset
                                })

    assert_includes svg,
                    '<text x="362" y="350" text-anchor="middle" font-family="Test Sans" font-size="13.0" fill="#1b1b1b">Month</text>'
    assert_includes svg, '<rect x="292" y="368" width="140" height="58" rx="10"'
  end

  def test_top_tick_stays_on_plot_boundary_when_axis_rounds_up
    svg = chart_renderer.render(@document, {
                                  'type' => 'column',
                                  'legend' => 'none',
                                  'dataset' => @dataset
                                })

    refute_includes svg, 'y1="-'
    refute_includes svg, 'y="-'
    assert_includes svg, '<line x1="92" y1="28.0" x2="632" y2="28.0" stroke="#d8d8d8" stroke-width="1"/>'
  end

  def test_category_axis_padding_moves_first_and_last_points_inside_plot
    svg = chart_renderer.render(@document, {
                                  'type' => 'line',
                                  'legend' => 'none',
                                  'category_axis_padding' => true,
                                  'dataset' => @dataset
                                })

    assert_includes svg, '<circle cx="182" cy="140" r="4" fill="#4b8bbf"/>'
    assert_includes svg, '<circle cx="542" cy="98" r="4" fill="#4b8bbf"/>'
    refute_includes svg, '<circle cx="92" cy="140" r="4" fill="#4b8bbf"/>'
    refute_includes svg, '<circle cx="632" cy="98" r="4" fill="#4b8bbf"/>'
  end

  def test_renders_area_chart_fill_and_stroke
    svg = chart_renderer.render(@document, {
                                  'type' => 'area',
                                  'legend' => 'none',
                                  'dataset' => @dataset
                                })

    assert_includes svg, 'fill-opacity="0.18"'
    assert_includes svg, 'fill="none" stroke="#4b8bbf"'
    assert_includes svg, 'fill="none" stroke="#c2410c"'
    assert_operator svg.scan(/fill-opacity="0\.18"/).length, :==, 2
  end

  def test_renders_secondary_axis_on_right_for_vertical_charts
    dataset = {
      'category_header' => 'month',
      'categories' => %w[Jan Feb Mar],
      'series' => [
        { 'name' => 'actual', 'title' => 'Revenue', 'axis' => 'primary', 'values' => [120.0, 180.0, 150.0] },
        { 'name' => 'variation', 'title' => 'Variation %', 'axis' => 'secondary', 'values' => [5.0, 12.0, 8.0] }
      ],
      'series_count' => 2,
      'row_count' => 3,
      'min_value' => 120.0,
      'max_value' => 180.0,
      'secondary_min_value' => 5.0,
      'secondary_max_value' => 12.0
    }

    svg = chart_renderer.render(@document, {
                                  'type' => 'line',
                                  'legend' => 'none',
                                  'y_axis_title' => 'Revenue',
                                  'secondary_axis' => { 'title' => 'Variation', 'format' => '%' },
                                  'dataset' => dataset
                                })

    assert_includes svg, '>Variation<'
    assert_includes svg, '<line x1="668" y1="28" x2="668" y2="308" stroke="#475569" stroke-width="1.5"/>'
    assert_includes svg,
                    '<text x="676" y="312" text-anchor="start" font-family="Test Sans" font-size="11.0" fill="#1b1b1b">0%</text>'
    assert_includes svg,
                    '<text x="676" y="32" text-anchor="start" font-family="Test Sans" font-size="11.0" fill="#1b1b1b">1500%</text>'
  end

  def test_renders_mixed_line_and_column_series
    dataset = {
      'category_header' => 'month',
      'categories' => %w[Jan Feb Mar],
      'series' => [
        { 'name' => 'actual', 'title' => 'Revenue', 'axis' => 'primary', 'values' => [12.0, 18.0, 15.0] },
        { 'name' => 'target', 'title' => 'Target', 'axis' => 'primary', 'type' => 'column',
          'values' => [10.0, 16.0, 17.0] }
      ],
      'series_count' => 2,
      'row_count' => 3,
      'min_value' => 10.0,
      'max_value' => 18.0
    }

    svg = chart_renderer.render(@document, {
                                  'type' => 'line',
                                  'legend' => 'none',
                                  'dataset' => dataset
                                })

    assert_includes svg, '<path d="M '
    assert_includes svg, '<circle '
    assert_operator svg.scan(%r{<rect [^>]*rx="2" [^>]*fill="#c2410c"[^>]*/>}).length, :==, 3
  end

  def test_area_fill_closes_back_to_zero_baseline
    svg = chart_renderer.render(@document, {
                                  'type' => 'area',
                                  'legend' => 'none',
                                  'dataset' => @dataset
                                })

    assert_match(/ Z"/, svg)
  end

  def test_area_legend_shows_line_and_fill_sample
    dataset = {
      'category_header' => 'month',
      'categories' => %w[Jan Feb Mar],
      'series' => [
        { 'name' => 'actual', 'title' => 'Revenue', 'axis' => 'primary', 'values' => [12.0, 18.0, 15.0] },
        { 'name' => 'forecast', 'title' => 'Forecast', 'axis' => 'primary', 'values' => [10.0, 16.0, 18.0] }
      ],
      'series_count' => 2,
      'row_count' => 3,
      'min_value' => 10.0,
      'max_value' => 18.0
    }

    svg = chart_renderer.render(@document, {
                                  'type' => 'area',
                                  'legend' => 'right',
                                  'dataset' => dataset
                                })

    assert_includes svg, '<line x1='
    assert_includes svg, 'fill-opacity="0.18"'
    assert_includes svg, '>Revenue<'
    assert_includes svg, '>Forecast<'
  end

  def test_negative_line_chart_renders_zero_axis_line
    neg_dataset = {
      'category_header' => 'month',
      'categories' => %w[Jan Feb Mar],
      'series' => [{ 'name' => 'delta', 'values' => [5.0, -3.0, 2.0] }],
      'series_count' => 1,
      'row_count' => 3,
      'min_value' => -3.0,
      'max_value' => 5.0
    }
    svg = chart_renderer.render(@document, {
                                  'type' => 'line',
                                  'legend' => 'none',
                                  'dataset' => neg_dataset
                                })

    assert_includes svg, 'stroke-width="1.5"/>'
    assert_includes svg, '>-4<'
    assert_includes svg, '>6<'
    refute_includes svg, 'y1="-'
    refute_includes svg, 'cy="-'
  end

  def test_negative_column_chart_bars_grow_from_zero
    neg_dataset = {
      'category_header' => 'month',
      'categories' => %w[Jan Feb],
      'series' => [{ 'name' => 'delta', 'values' => [4.0, -4.0] }],
      'series_count' => 1,
      'row_count' => 2,
      'min_value' => -4.0,
      'max_value' => 4.0
    }
    svg = chart_renderer.render(@document, {
                                  'type' => 'column',
                                  'legend' => 'none',
                                  'dataset' => neg_dataset
                                })

    rects = svg.scan(%r{<rect [^>]*fill="#4b8bbf"[^>]*/>})
    heights = rects.map { |r| r.match(/height="([^"]+)"/)[1].to_f }
    assert_equal 2, rects.length
    assert heights.all? { |h| h > 0 }, 'all bars must have positive height'
    assert heights.all? { |h|
      h == heights[0]
    }, 'positive and negative bars with equal magnitude must have equal height'
  end

  def test_negative_bar_chart_bars_grow_from_zero
    neg_dataset = {
      'category_header' => 'month',
      'categories' => %w[Jan Feb],
      'series' => [{ 'name' => 'delta', 'values' => [4.0, -4.0] }],
      'series_count' => 1,
      'row_count' => 2,
      'min_value' => -4.0,
      'max_value' => 4.0
    }
    svg = chart_renderer.render(@document, {
                                  'type' => 'bar',
                                  'legend' => 'none',
                                  'dataset' => neg_dataset
                                })

    rects = svg.scan(%r{<rect [^>]*fill="#4b8bbf"[^>]*/>})
    widths = rects.map { |r| r.match(/width="([^"]+)"/)[1].to_f }
    assert_equal 2, rects.length
    assert widths.all? { |w| w > 0 }, 'all bars must have positive width'
    assert widths.all? { |w| w == widths[0] }, 'positive and negative bars with equal magnitude must have equal width'
  end
end
