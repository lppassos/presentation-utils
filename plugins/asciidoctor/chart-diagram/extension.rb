require 'asciidoctor'
require 'asciidoctor/extensions'
require 'asciidoctor-pdf'
require 'csv'
require 'fileutils'
require 'pathname'
require 'securerandom'
require 'yaml'

module PresentationUtils
  module ChartDiagram
    class Error < StandardError; end

    class Parser
      SUPPORTED_TYPES = %w[line area bar column].freeze
      SUPPORTED_LEGENDS = %w[none left right bottom top-left top-right].freeze

      def parse(content_or_lines, document)
        content = Array(content_or_lines).join("\n")
        raw = parse_yaml(content)
        config = normalize_config(raw)
        csv_text = load_csv_text(config, document)
        dataset = parse_dataset(csv_text, config)

        config.merge('dataset' => dataset)
      end

      private

      def parse_yaml(content)
        parsed = YAML.safe_load(content, permitted_classes: [], aliases: false)
        raise Error, 'chart block must contain a YAML mapping' unless parsed.is_a?(Hash)

        parsed
      rescue Psych::SyntaxError => e
        raise Error, "invalid chart YAML: #{e.message.lines.first.to_s.strip}"
      end

      def normalize_config(raw)
        config = raw.each_with_object({}) { |(key, value), memo| memo[key.to_s] = value }

        type = config['type'].to_s.strip
        raise Error, 'chart type is required' if type.empty?
        raise Error, "unsupported chart type: #{type}" unless SUPPORTED_TYPES.include?(type)

        has_inline = !blank?(config['data'])
        has_file = !blank?(config['data_file'])
        raise Error, 'chart must define exactly one of data or data_file' if has_inline == has_file

        legend = config['legend'].to_s.strip
        legend = 'none' if legend.empty?
        raise Error, "unsupported legend value: #{legend}" unless SUPPORTED_LEGENDS.include?(legend)

        series = config['series']
        if series.nil?
          normalized_series = nil
        elsif series.is_a?(Array)
          normalized_series = series.map(&:to_s).map(&:strip).reject(&:empty?)
          raise Error, 'series must include at least one column name when provided' if normalized_series.empty?
        else
          raise Error, 'series must be a YAML list of column names'
        end

        override_series = config['override_series']
        if override_series.nil?
          normalized_override_series = []
        elsif override_series.is_a?(Array)
          normalized_override_series = override_series.map { |entry| normalize_series_override(entry) }
          if normalized_override_series.empty?
            raise Error,
                  'override_series must include at least one series override when provided'
          end

          override_names = normalized_override_series.map { |entry| entry['name'] }
          raise Error, 'override_series names must be unique' unless override_names.uniq.length == override_names.length
        else
          raise Error, 'override_series must be a YAML list of objects'
        end

        if type == 'bar' && normalized_override_series.any? { |entry| entry['axis'] == 'secondary' }
          raise Error, 'override_series with axis secondary is not supported for bar charts'
        end

        if type == 'bar' && normalized_override_series.any? { |entry| entry['type'] && entry['type'] != 'bar' }
          raise Error, 'override_series type overrides are not supported for bar charts'
        end

        if type != 'bar' && normalized_override_series.any? { |entry| entry['type'] == 'bar' }
          raise Error, 'override_series type bar is only supported for bar charts'
        end

        secondary_axis = normalize_secondary_axis(config['secondary_axis'])
        category_axis_padding = normalize_boolean(config['category_axis_padding'], 'category_axis_padding')

        {
          'type' => type,
          'title' => string_or_nil(config['title']),
          'x_axis_title' => string_or_nil(config['x_axis_title']),
          'y_axis_title' => string_or_nil(config['y_axis_title']),
          'secondary_axis' => secondary_axis,
          'series' => normalized_series,
          'override_series' => normalized_override_series,
          'legend' => legend,
          'category_axis_padding' => category_axis_padding,
          'data' => has_inline ? config['data'].to_s : nil,
          'data_file' => has_file ? config['data_file'].to_s.strip : nil
        }
      end

      def load_csv_text(config, document)
        return config['data'] if config['data']

        path = resolve_data_file_path(document, config['data_file'])
        raise Error, "chart data file not found: #{config['data_file']}" unless File.file?(path)

        File.read(path)
      rescue Errno::ENOENT
        raise Error, "chart data file not found: #{config['data_file']}"
      end

      def resolve_data_file_path(document, target)
        return target if Pathname.new(target).absolute?

        docdir = document.attr('docdir') || Dir.pwd
        docfile = document.attr('docfile')
        base_dir = if docfile && !docfile.to_s.empty?
                     File.dirname(File.expand_path(docfile,
                                                   docdir))
                   else
                     File.expand_path(docdir)
                   end
        File.expand_path(target, base_dir)
      end

      def parse_dataset(csv_text, config)
        rows = CSV.parse(csv_text.to_s, headers: false).map { |row| Array(row).map { |value| value.to_s.strip } }
        rows = rows.compact.reject { |row| row.empty? || row.all?(&:empty?) }

        raise Error, 'chart CSV must contain a header row and at least one data row' if rows.length < 2

        headers = rows.first
        raise Error, 'chart CSV must have at least two columns' if headers.length < 2
        raise Error, 'chart CSV headers must be unique' unless headers.uniq.length == headers.length

        data_rows = rows.drop(1)
        data_rows.each do |row|
          raise Error, 'chart CSV rows must match the header column count' unless row.length == headers.length
        end

        selected_series = config['series'] || headers.drop(1)
        missing_series = selected_series - headers.drop(1)
        raise Error, "unknown series column(s): #{missing_series.join(', ')}" unless missing_series.empty?

        override_series = config['override_series'] || []
        override_names = override_series.map { |entry| entry['name'] }
        missing_override_series = override_names - selected_series
        unless missing_override_series.empty?
          raise Error,
                "unknown override series column(s): #{missing_override_series.join(', ')}"
        end

        secondary_series_count = override_series.count { |entry| entry['axis'] == 'secondary' }
        if !override_series.empty? && secondary_series_count == selected_series.length
          raise Error,
                'override_series must leave at least one primary-axis series'
        end

        override_map = override_series.each_with_object({}) { |entry, memo| memo[entry['name']] = entry }

        series_indexes = selected_series.map { |name| headers.index(name) }
        categories = []
        series = selected_series.map do |name|
          override = override_map[name] || {}
          {
            'name' => name,
            'title' => override['title'] || name,
            'axis' => override['axis'] || 'primary',
            'type' => override['type'],
            'values' => []
          }
        end

        data_rows.each do |row|
          categories << row[0].to_s
          series_indexes.each_with_index do |index, series_idx|
            raw_value = row[index].to_s
            begin
              value = Float(raw_value)
            rescue ArgumentError
              raise Error, "chart series values must be numeric: #{raw_value.inspect} in column #{headers[index]}"
            end
            series[series_idx]['values'] << value
          end
        end

        primary_values = series.select { |entry| entry['axis'] == 'primary' }.flat_map { |entry| entry['values'] }
        secondary_values = series.select { |entry| entry['axis'] == 'secondary' }.flat_map { |entry| entry['values'] }
        {
          'category_header' => headers.first,
          'categories' => categories,
          'series' => series,
          'series_count' => series.length,
          'row_count' => categories.length,
          'min_value' => primary_values.min.to_f,
          'max_value' => primary_values.max.to_f,
          'secondary_min_value' => secondary_values.min&.to_f,
          'secondary_max_value' => secondary_values.max&.to_f
        }
      rescue CSV::MalformedCSVError => e
        raise Error, "invalid chart CSV: #{e.message}"
      end

      def string_or_nil(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def normalize_boolean(value, key)
        return false if value.nil?
        return value if [true, false].include?(value)

        normalized = value.to_s.strip.downcase
        return true if normalized == 'true'
        return false if normalized == 'false'

        raise Error, "#{key} must be true or false"
      end

      def normalize_series_override(entry)
        raise Error, 'override_series entries must be YAML objects' unless entry.is_a?(Hash)

        normalized = entry.each_with_object({}) { |(key, value), memo| memo[key.to_s] = value }
        name = normalized['name'].to_s.strip
        raise Error, 'override_series entries must define a name' if name.empty?

        axis = normalized['axis'].to_s.strip
        axis = 'primary' if axis.empty?
        raise Error, "unsupported override_series axis: #{axis}" unless %w[primary secondary].include?(axis)

        {
          'name' => name,
          'title' => string_or_nil(normalized['title']),
          'axis' => axis,
          'type' => normalize_series_type(normalized['type'])
        }
      end

      def normalize_series_type(value)
        return nil if value.nil?

        type = value.to_s.strip
        return nil if type.empty?

        raise Error, "unsupported override_series type: #{type}" unless SUPPORTED_TYPES.include?(type)

        type
      end

      def normalize_secondary_axis(value)
        return nil if value.nil?

        raise Error, 'secondary_axis must be a YAML object' unless value.is_a?(Hash)

        normalized = value.each_with_object({}) { |(key, entry_value), memo| memo[key.to_s] = entry_value }
        format = normalized['format'].to_s.strip
        format = '#' if format.empty?
        raise Error, "unsupported secondary_axis format: #{format}" unless ['#', '%'].include?(format)

        {
          'title' => string_or_nil(normalized['title']),
          'format' => format
        }
      end

      def blank?(value)
        value.nil? || value.to_s.strip.empty?
      end
    end

    class ChartBlockProcessor < Asciidoctor::Extensions::BlockProcessor
      use_dsl
      named :chart
      on_context :listing
      parse_content_as :raw

      def process(parent, reader, attrs)
        data = Parser.new.parse(reader.lines, parent.document)

        create_block parent, :open, nil, attrs.merge({
                                                       'role' => 'chart-diagram',
                                                       'chart-diagram-data' => data
                                                     })
      rescue Error => e
        raise Asciidoctor::Error, "chart block error: #{e.message}"
      end
    end

    class Renderer
      LEGEND_OUTSIDE = %w[left right bottom].freeze

      def render(document, data, theme: nil)
        settings = settings(document, theme)
        dataset = data.fetch('dataset')
        layout = build_layout(data, dataset, settings)
        svg = []
        svg << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{layout[:width]}" height="#{layout[:height]}" viewBox="0 0 #{layout[:width]} #{layout[:height]}">)
        svg << %(<rect x="0" y="0" width="#{layout[:width]}" height="#{layout[:height]}" fill="#{settings[:background_color]}"/>)
        svg.concat(render_grid_and_axes(data, dataset, layout, settings))
        svg.concat(render_series(data, dataset, layout, settings))
        svg.concat(render_labels(data, dataset, layout, settings))
        svg.concat(render_legend(dataset, data['type'], data['legend'], layout, settings))
        svg << '</svg>'
        svg.join("\n")
      end

      def settings(document, theme)
        palette = get_setting(document, theme, 'chart-diagram-series-palette', :chart_diagram_series_palette,
                              '#4b8bbf,#c2410c,#2b7a78,#7c3aed,#ca8a04,#be185d')
        {
          background_color: get_setting(document, theme, 'chart-diagram-background-color', :chart_diagram_background_color,
                                        '#ffffff'),
          font_family: get_setting(document, theme, 'chart-diagram-font-family', :chart_diagram_font_family,
                                   document.attr('base-font-family') || 'Arial, sans-serif'),
          font_size: get_setting(document, theme, 'chart-diagram-font-size', :chart_diagram_font_size, 12).to_f,
          title_font_size: get_setting(document, theme, 'chart-diagram-title-font-size', :chart_diagram_title_font_size,
                                       18).to_f,
          axis_title_font_size: get_setting(document, theme, 'chart-diagram-axis-title-font-size', :chart_diagram_axis_title_font_size,
                                            13).to_f,
          tick_font_size: get_setting(document, theme, 'chart-diagram-tick-font-size', :chart_diagram_tick_font_size,
                                      11).to_f,
          text_color: get_setting(document, theme, 'chart-diagram-text-color', :chart_diagram_text_color, '#1b1b1b'),
          title_color: get_setting(document, theme, 'chart-diagram-title-color', :chart_diagram_title_color, '#101010'),
          axis_color: get_setting(document, theme, 'chart-diagram-axis-color', :chart_diagram_axis_color, '#475569'),
          grid_color: get_setting(document, theme, 'chart-diagram-grid-color', :chart_diagram_grid_color, '#d8d8d8'),
          legend_text_color: get_setting(document, theme, 'chart-diagram-legend-text-color', :chart_diagram_legend_text_color,
                                         '#1b1b1b'),
          legend_border_color: get_setting(document, theme, 'chart-diagram-legend-border-color', :chart_diagram_legend_border_color,
                                           '#94a3b8'),
          legend_background_color: get_setting(document, theme, 'chart-diagram-legend-background-color', :chart_diagram_legend_background_color,
                                               '#ffffff'),
          palette: palette.to_s.split(',').map(&:strip).reject(&:empty?)
        }
      end

      private

      def build_layout(data, dataset, settings)
        title_height = data['title'] ? 38 : 10
        bottom_axis_title_present = data['type'] == 'bar' ? !!data['y_axis_title'] : !!data['x_axis_title']
        bottom_axis_title_height = bottom_axis_title_present ? 28 : 8
        has_secondary_axis = !dataset['secondary_min_value'].nil? && !dataset['secondary_max_value'].nil?
        left_axis_title_width = if data['type'] == 'bar'
                                  data['x_axis_title'] ? 36 : 0
                                else
                                  (data['y_axis_title'] ? 36 : 0)
                                end
        right_axis_title_width = has_secondary_axis && data['type'] != 'bar' && secondary_axis_title(data) ? 36 : 0
        right_padding = has_secondary_axis && data['type'] != 'bar' ? 92 + right_axis_title_width : 24
        top_padding = 18
        plot_x = 92 + left_axis_title_width
        plot_y = top_padding + title_height
        plot_width = 540
        plot_height = 280
        legend_size = legend_size(dataset, settings, data['legend'])
        bottom_legend_gap = data['legend'] == 'bottom' ? 18 : 0

        if data['legend'] == 'left'
          plot_x += legend_size[:width] + 18
        elsif data['legend'] == 'right'
          right_padding += legend_size[:width] + 18
        end
        bottom_axis_title_height += legend_size[:height] + bottom_legend_gap + 16 if data['legend'] == 'bottom'

        width = plot_x + plot_width + right_padding
        height = plot_y + plot_height + 52 + bottom_axis_title_height

        ticks = nice_ticks(dataset['min_value'], dataset['max_value'])
        secondary_ticks = if has_secondary_axis
                            nice_ticks(dataset['secondary_min_value'],
                                       dataset['secondary_max_value'])
                          end
        {
          width: width,
          height: height,
          plot_x: plot_x,
          plot_y: plot_y,
          plot_width: plot_width,
          plot_height: plot_height,
          title_y: 28,
          ticks: ticks,
          axis_min: ticks.min.to_f,
          axis_max: ticks.max.to_f,
          secondary_ticks: secondary_ticks,
          secondary_axis_min: secondary_ticks&.min&.to_f,
          secondary_axis_max: secondary_ticks&.max&.to_f,
          has_secondary_axis: has_secondary_axis,
          category_axis_padding: data['category_axis_padding'],
          bottom_axis_title_present: bottom_axis_title_present,
          bottom_legend_gap: bottom_legend_gap,
          legend_box: legend_box(data['legend'], legend_size, plot_x, plot_y, plot_width, plot_height, width, height,
                                 bottom_axis_title_present, bottom_legend_gap),
          left_axis_title_width: left_axis_title_width,
          right_axis_title_width: right_axis_title_width
        }
      end

      def legend_size(dataset, settings, legend)
        return { width: 0, height: 0 } if legend.to_s == 'none'

        max_name = dataset['series'].map { |entry| entry['name'].to_s.length }.max || 0
        item_height = settings[:tick_font_size] + 10
        {
          width: [140, 48 + (max_name * (settings[:tick_font_size] * 0.55))].max,
          height: 16 + (dataset['series'].length * item_height)
        }
      end

      def legend_box(legend, legend_size, plot_x, plot_y, plot_width, plot_height, width, _height,
                     bottom_axis_title_present, bottom_legend_gap)
        return nil if legend.to_s == 'none'

        case legend
        when 'left'
          { x: plot_x - legend_size[:width] - 18, y: plot_y + 8, width: legend_size[:width],
            height: legend_size[:height] }
        when 'right'
          { x: plot_x + plot_width + 18, y: plot_y + 8, width: legend_size[:width], height: legend_size[:height] }
        when 'bottom'
          legend_y = plot_y + plot_height + (bottom_axis_title_present ? 42 + bottom_legend_gap : 42)
          { x: plot_x + ((plot_width - legend_size[:width]) / 2.0), y: legend_y, width: legend_size[:width],
            height: legend_size[:height] }
        when 'top-left'
          { x: plot_x + 12, y: plot_y + 12, width: legend_size[:width], height: legend_size[:height] }
        when 'top-right'
          { x: [plot_x + 12, plot_x + plot_width - legend_size[:width] - 12].max, y: plot_y + 12,
            width: legend_size[:width], height: legend_size[:height] }
        else
          { x: width - legend_size[:width] - 24, y: plot_y + 8, width: legend_size[:width],
            height: legend_size[:height] }
        end
      end

      def render_grid_and_axes(data, dataset, layout, settings)
        lines = []
        plot_x = layout[:plot_x]
        plot_y = layout[:plot_y]
        plot_width = layout[:plot_width]
        plot_height = layout[:plot_height]
        has_negatives = layout[:axis_min] < 0.0

        lines << %(<line x1="#{plot_x}" y1="#{plot_y}" x2="#{plot_x}" y2="#{plot_y + plot_height}" stroke="#{settings[:axis_color]}" stroke-width="1.5"/>)
        lines << %(<line x1="#{plot_x}" y1="#{plot_y + plot_height}" x2="#{plot_x + plot_width}" y2="#{plot_y + plot_height}" stroke="#{settings[:axis_color]}" stroke-width="1.5"/>)

        if data['type'] == 'bar'
          layout[:ticks].each do |tick|
            x = value_to_x(tick, layout, dataset)
            lines << %(<line x1="#{x}" y1="#{plot_y}" x2="#{x}" y2="#{plot_y + plot_height}" stroke="#{settings[:grid_color]}" stroke-width="1"/>)
            lines << text(x, plot_y + plot_height + 18, tick_label(tick), settings[:font_family], settings[:tick_font_size],
                          settings[:text_color], anchor: 'middle')
          end

          if has_negatives
            zero_x = value_to_x(0.0, layout, dataset)
            lines << %(<line x1="#{format_number(zero_x)}" y1="#{plot_y}" x2="#{format_number(zero_x)}" y2="#{plot_y + plot_height}" stroke="#{settings[:axis_color]}" stroke-width="1.5"/>)
          end

          dataset['categories'].each_with_index do |label, index|
            y = bar_category_center(index, dataset, layout)
            lines << text(plot_x - 10, y + 4, label, settings[:font_family], settings[:tick_font_size],
                          settings[:text_color], anchor: 'end')
          end
        else
          layout[:ticks].each do |tick|
            y = value_to_y(tick, layout, dataset)
            lines << %(<line x1="#{plot_x}" y1="#{y}" x2="#{plot_x + plot_width}" y2="#{y}" stroke="#{settings[:grid_color]}" stroke-width="1"/>)
            lines << text(plot_x - 8, y + 4, tick_label(tick), settings[:font_family], settings[:tick_font_size],
                          settings[:text_color], anchor: 'end')
          end

          if layout[:has_secondary_axis]
            right_axis_x = plot_x + plot_width
            lines << %(<line x1="#{right_axis_x}" y1="#{plot_y}" x2="#{right_axis_x}" y2="#{plot_y + plot_height}" stroke="#{settings[:axis_color]}" stroke-width="1.5"/>)
            layout[:secondary_ticks].each do |tick|
              y = value_to_y(tick, layout, dataset, axis: 'secondary')
              lines << text(right_axis_x + 8, y + 4, tick_label(tick, secondary_axis_format(data)), settings[:font_family], settings[:tick_font_size],
                            settings[:text_color], anchor: 'start')
            end
          end

          if has_negatives
            zero_y = value_to_y(0.0, layout, dataset)
            lines << %(<line x1="#{plot_x}" y1="#{format_number(zero_y)}" x2="#{plot_x + plot_width}" y2="#{format_number(zero_y)}" stroke="#{settings[:axis_color]}" stroke-width="1.5"/>)
          end

          dataset['categories'].each_with_index do |label, index|
            x = category_center(index, dataset, layout)
            lines << text(x, plot_y + plot_height + 18, label, settings[:font_family], settings[:tick_font_size],
                          settings[:text_color], anchor: 'middle')
          end
        end

        lines
      end

      def render_series(data, dataset, layout, settings)
        case data['type']
        when 'bar' then render_bar_series(dataset, layout, settings)
        else
          render_mixed_vertical_series(data, dataset, layout, settings)
        end
      end

      def render_mixed_vertical_series(data, dataset, layout, settings)
        %w[column area line].flat_map do |series_type|
          dataset['series'].each_with_index.filter_map do |series, idx|
            render_series_entry(data, dataset, layout, settings, series, idx) if resolved_series_type(data,
                                                                                                      series) == series_type
          end
        end
      end

      def render_series_entry(data, dataset, layout, settings, series, idx)
        case resolved_series_type(data, series)
        when 'line' then render_line_series_entry(dataset, layout, settings, series, idx)
        when 'area' then render_area_series_entry(dataset, layout, settings, series, idx)
        when 'column' then render_column_series_entry(data, dataset, layout, settings, series, idx)
        end
      end

      def render_line_series_entry(dataset, layout, settings, series, idx)
        color = palette_color(settings, idx)
        points = series['values'].each_with_index.map do |value, category_index|
          [category_center(category_index, dataset, layout), value_to_y(value, layout, dataset, axis: series['axis'])]
        end
        path = points.each_with_index.map do |(x, y), i|
          "#{i.zero? ? 'M' : 'L'} #{format_number(x)} #{format_number(y)}"
        end.join(' ')
        lines = []
        lines << %(<path d="#{path}" fill="none" stroke="#{color}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>)
        points.each do |x, y|
          lines << %(<circle cx="#{format_number(x)}" cy="#{format_number(y)}" r="4" fill="#{color}"/>)
        end
        lines
      end

      def render_area_series_entry(dataset, layout, settings, series, idx)
        color = palette_color(settings, idx)
        zero_y = value_to_y(0.0, layout, dataset, axis: series['axis'])
        points = series['values'].each_with_index.map do |value, category_index|
          [category_center(category_index, dataset, layout), value_to_y(value, layout, dataset, axis: series['axis'])]
        end
        line_d = points.each_with_index.map do |(x, y), i|
          "#{i.zero? ? 'M' : 'L'} #{format_number(x)} #{format_number(y)}"
        end.join(' ')
        first_x = format_number(points.first[0])
        last_x  = format_number(points.last[0])
        fill_d  = "#{line_d} L #{last_x} #{format_number(zero_y)} L #{first_x} #{format_number(zero_y)} Z"
        [
          %(<path d="#{fill_d}" fill="#{color}" fill-opacity="0.18" stroke="none"/>),
          %(<path d="#{line_d}" fill="none" stroke="#{color}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>)
        ]
      end

      def render_column_series_entry(data, dataset, layout, settings, series, series_idx)
        column_series_indexes = dataset['series'].each_index.select do |index|
          resolved_series_type(data, dataset['series'][index]) == 'column'
        end
        category_width = layout[:plot_width].to_f / dataset['row_count']
        inner_gap = 6.0
        group_width = [category_width - 16.0, 20.0].max
        bar_width = [(group_width - (inner_gap * (column_series_indexes.length - 1))) / column_series_indexes.length,
                     6.0].max
        column_position = column_series_indexes.index(series_idx)
        color = palette_color(settings, series_idx)
        zero_y = value_to_y(0.0, layout, dataset, axis: series['axis'])

        series['values'].each_with_index.map do |value, cat_idx|
          x = layout[:plot_x] + (cat_idx * category_width) + ((category_width - group_width) / 2.0) + (column_position * (bar_width + inner_gap))
          y = value_to_y(value, layout, dataset, axis: series['axis'])
          rect_y = [y, zero_y].min
          h = [(zero_y - y).abs, 1.0].max
          %(<rect x="#{format_number(x)}" y="#{format_number(rect_y)}" width="#{format_number(bar_width)}" height="#{format_number(h)}" rx="2" fill="#{color}"/>)
        end
      end

      def render_bar_series(dataset, layout, settings)
        category_height = layout[:plot_height].to_f / dataset['row_count']
        inner_gap = 6.0
        group_height = [category_height - 16.0, 18.0].max
        bar_height = [(group_height - (inner_gap * (dataset['series_count'] - 1))) / dataset['series_count'], 6.0].max
        zero_x = value_to_x(0.0, layout, dataset)

        dataset['series'].each_with_index.flat_map do |series, series_idx|
          color = palette_color(settings, series_idx)
          series['values'].each_with_index.map do |value, cat_idx|
            y = layout[:plot_y] + (cat_idx * category_height) + ((category_height - group_height) / 2.0) + (series_idx * (bar_height + inner_gap))
            x = value_to_x(value, layout, dataset)
            rect_x = [x, zero_x].min
            w = [(x - zero_x).abs, 1.0].max
            %(<rect x="#{format_number(rect_x)}" y="#{format_number(y)}" width="#{format_number(w)}" height="#{format_number(bar_height)}" rx="2" fill="#{color}"/>)
          end
        end
      end

      def render_labels(data, _dataset, layout, settings)
        lines = []
        if data['title']
          lines << text(layout[:plot_x] + (layout[:plot_width] / 2.0), layout[:title_y], data['title'],
                        settings[:font_family], settings[:title_font_size], settings[:title_color], anchor: 'middle', weight: 700)
        end

        plot_center_x = layout[:plot_x] + (layout[:plot_width] / 2.0)
        plot_bottom_y = layout[:plot_y] + layout[:plot_height]
        axis_title_value = data['type'] == 'bar' ? data['x_axis_title'] : data['y_axis_title']
        if axis_title_value
          lines << %(<text x="#{format_number(layout[:plot_x] - 58)}" y="#{format_number(layout[:plot_y] + (layout[:plot_height] / 2.0))}" text-anchor="middle" font-family="#{escape_xml(settings[:font_family])}" font-size="#{settings[:axis_title_font_size]}" fill="#{settings[:text_color]}" transform="rotate(-90 #{format_number(layout[:plot_x] - 58)} #{format_number(layout[:plot_y] + (layout[:plot_height] / 2.0))})">#{escape_xml(axis_title_value)}</text>)
        end

        if layout[:has_secondary_axis] && data['type'] != 'bar' && secondary_axis_title(data)
          x = layout[:plot_x] + layout[:plot_width] + 58
          y = layout[:plot_y] + (layout[:plot_height] / 2.0)
          lines << %(<text x="#{format_number(x)}" y="#{format_number(y)}" text-anchor="middle" font-family="#{escape_xml(settings[:font_family])}" font-size="#{settings[:axis_title_font_size]}" fill="#{settings[:text_color]}" transform="rotate(90 #{format_number(x)} #{format_number(y)})">#{escape_xml(secondary_axis_title(data))}</text>)
        end

        category_axis_title = data['type'] == 'bar' ? data['y_axis_title'] : data['x_axis_title']
        if category_axis_title
          lines << text(plot_center_x, plot_bottom_y + 42, category_axis_title, settings[:font_family],
                        settings[:axis_title_font_size], settings[:text_color], anchor: 'middle')
        end
        lines
      end

      def render_legend(dataset, chart_type, legend, layout, settings)
        return [] if legend.to_s == 'none'

        box = layout[:legend_box]
        lines = []
        lines << %(<rect x="#{format_number(box[:x])}" y="#{format_number(box[:y])}" width="#{format_number(box[:width])}" height="#{format_number(box[:height])}" rx="10" fill="#{settings[:legend_background_color]}" stroke="#{settings[:legend_border_color]}" stroke-width="1.5"/>)
        dataset['series'].each_with_index do |series, index|
          y = box[:y] + 18 + (index * (settings[:tick_font_size] + 10))
          color = palette_color(settings, index)
          series_type = resolved_series_type({ 'type' => chart_type }, series)
          if %w[line area].include?(series_type)
            lines << %(<line x1="#{format_number(box[:x] + 12)}" y1="#{format_number(y - 4)}" x2="#{format_number(box[:x] + 32)}" y2="#{format_number(y - 4)}" stroke="#{color}" stroke-width="3" stroke-linecap="round"/>)
            lines << %(<circle cx="#{format_number(box[:x] + 22)}" cy="#{format_number(y - 4)}" r="3" fill="#{color}"/>)
            if series_type == 'area'
              lines << %(<rect x="#{format_number(box[:x] + 12)}" y="#{format_number(y - 1)}" width="20" height="6" fill="#{color}" fill-opacity="0.18" stroke="none"/>)
            end
          else
            lines << %(<rect x="#{format_number(box[:x] + 12)}" y="#{format_number(y - 10)}" width="18" height="10" rx="2" fill="#{color}"/>)
          end
          lines << text(box[:x] + 38, y, series['title'] || series['name'], settings[:font_family], settings[:tick_font_size],
                        settings[:legend_text_color])
        end
        lines
      end

      def category_center(index, dataset, layout)
        return layout[:plot_x] + (layout[:plot_width] / 2.0) if dataset['row_count'] <= 1

        if layout[:category_axis_padding]
          spacing = layout[:plot_width].to_f / dataset['row_count']
          layout[:plot_x] + ((index + 0.5) * spacing)
        else
          spacing = layout[:plot_width].to_f / (dataset['row_count'] - 1)
          layout[:plot_x] + (index * spacing)
        end
      end

      def bar_category_center(index, dataset, layout)
        category_height = layout[:plot_height].to_f / dataset['row_count']
        layout[:plot_y] + (index * category_height) + (category_height / 2.0)
      end

      def value_to_y(value, layout, dataset, axis: 'primary')
        axis_min, axis_max, min_value, max_value = axis_scale(axis, layout, dataset)
        range = [axis_max - axis_min, max_value - min_value, 1.0].max
        layout[:plot_y] + layout[:plot_height] - (((value.to_f - axis_min) / range) * layout[:plot_height])
      end

      def value_to_x(value, layout, dataset)
        range = [layout[:axis_max].to_f - layout[:axis_min].to_f,
                 dataset['max_value'].to_f - dataset['min_value'].to_f, 1.0].max
        layout[:plot_x] + (((value.to_f - layout[:axis_min].to_f) / range) * layout[:plot_width])
      end

      def axis_scale(axis, layout, dataset)
        if axis.to_s == 'secondary'
          [layout[:secondary_axis_min].to_f, layout[:secondary_axis_max].to_f,
           dataset['secondary_min_value'].to_f, dataset['secondary_max_value'].to_f]
        else
          [layout[:axis_min].to_f, layout[:axis_max].to_f, dataset['min_value'].to_f, dataset['max_value'].to_f]
        end
      end

      def nice_ticks(min_value, max_value)
        min_value = min_value.to_f
        max_value = max_value.to_f
        min_value = 0.0 if min_value > 0.0
        max_value = 0.0 if max_value < 0.0

        span = max_value - min_value
        return [min_value, max_value == min_value ? min_value + 1.0 : max_value] if span <= 1.0

        rough_step = span / 5.0
        magnitude = 10**Math.log10(rough_step).floor
        step = [1, 2, 5, 10].map { |f| f * magnitude }.find { |c| c >= rough_step } || magnitude

        tick_min = (min_value / step).floor * step
        tick_max = (max_value / step).ceil * step

        ticks = []
        current = tick_min
        while current <= tick_max + (step / 10.0)
          ticks << current.round(10)
          current += step
        end
        ticks
      end

      def tick_label(value, axis_format = '#')
        return percentage_tick_label(value) if axis_format == '%'

        value == value.to_i ? value.to_i.to_s : format('%.2f', value).sub(/0+\z/, '').sub(/\.\z/, '')
      end

      def percentage_tick_label(value)
        scaled = value.to_f * 100.0
        "#{tick_label(scaled, '#')}%"
      end

      def secondary_axis_title(data)
        data['secondary_axis'] && data['secondary_axis']['title']
      end

      def secondary_axis_format(data)
        data['secondary_axis'] && data['secondary_axis']['format'] ? data['secondary_axis']['format'] : '#'
      end

      def resolved_series_type(data, series)
        series['type'] || data['type']
      end

      def text(x, y, content, font_family, font_size, fill, anchor: 'start', weight: nil)
        weight_attr = weight ? %( font-weight="#{weight}") : ''
        %(<text x="#{format_number(x)}" y="#{format_number(y)}" text-anchor="#{anchor}" font-family="#{escape_xml(font_family)}" font-size="#{font_size}" fill="#{fill}"#{weight_attr}>#{escape_xml(content)}</text>)
      end

      def get_setting(document, theme, attr_name, theme_name, default)
        attr_value = document.attr(attr_name)
        return attr_value unless attr_value.nil? || attr_value.to_s.empty?

        theme_value = theme[theme_name] if theme
        return normalize_color_value(theme_value, default) unless theme_value.nil?

        default
      end

      def normalize_color_value(value, default)
        return value unless default.to_s.start_with?('#')

        value.to_s.start_with?('#') ? value : "##{value}"
      end

      def palette_color(settings, index)
        palette = settings[:palette]
        palette[index % palette.length]
      end

      def escape_xml(text)
        text.to_s
            .gsub('&', '&amp;')
            .gsub('<', '&lt;')
            .gsub('>', '&gt;')
            .gsub('"', '&quot;')
      end

      def format_number(value)
        format('%.2f', value.to_f).sub(/\.00\z/, '').sub(/(\.\d)0\z/, '\\1')
      end
    end

    class ChartBlockConverter < (Asciidoctor::Converter.for 'pdf')
      register_for 'pdf'

      def convert_open(node)
        return super unless node.role == 'chart-diagram'

        data = node.attr('chart-diagram-data') || {}
        target = node.attr('target')
        target = "chart-diagram-#{SecureRandom.hex(4)}.svg" if target.nil? || target.strip.empty?
        target = normalize_target(target)

        output_path = resolve_output_path(node.document, target)
        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, render_chart_svg(node.document, data))

        render_image = ::Asciidoctor::Block.new(
          node.parent,
          :image,
          source: nil,
          attributes: {
            'target' => output_path,
            'alt' => 'Chart diagram'
          }
        )

        convert_image render_image
      end

      def normalize_target(target)
        normalized = target.strip
        if normalized =~ /\.[^.]+\z/
          normalized.sub(/\.[^.]+\z/, '.svg')
        else
          "#{normalized}.svg"
        end
      end

      def resolve_output_path(document, target)
        images_outdir = document.attr('imagesoutdir') || document.attr('imagesdir') || '.'
        docdir = document.attr('docdir') || Dir.pwd
        images_outdir = File.expand_path(images_outdir, docdir) unless Pathname.new(images_outdir).absolute?

        return target if Pathname.new(target).absolute?

        File.join(images_outdir, target)
      end

      def render_chart_svg(document, data)
        Renderer.new.render(document, data, theme: current_theme)
      end

      def current_theme
        respond_to?(:theme) ? theme : nil
      end
    end
  end
end

Asciidoctor::Extensions.register do
  block PresentationUtils::ChartDiagram::ChartBlockProcessor
end
