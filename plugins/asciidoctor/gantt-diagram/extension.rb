require "asciidoctor"
require "asciidoctor/extensions"
require "fileutils"
require "securerandom"

module PresentationUtils
  module GanttDiagram
    class GanttBlockProcessor < Asciidoctor::Extensions::BlockProcessor
      include Asciidoctor::Logging

      use_dsl
      named :gantt
      on_context :listing
      parse_content_as :raw

      def process(parent, reader, attrs)
        document = parent.document
        lines = reader.lines

        period = "week"
        activities = []

        in_activities = false
        raw_entries = []

        lines.each do |line|
          stripped = line.strip
          next if stripped.empty?

          if stripped.start_with?("period:")
            value = stripped.split(":", 2)[1].to_s.strip
            period = value.gsub(/\A"|"\z/, "")
            next
          end

          if stripped.start_with?("activities:")
            in_activities = true
            next
          end

          next unless in_activities

          indent = line[/\A[\t ]*/].to_s.gsub("\t", "  ").length
          activity = parse_activity(stripped)
          raw_entries << {indent: indent, activity: activity} if activity
        end

        activities = apply_grouping(raw_entries)

        computed = compute_schedule(activities)
        total_units = computed.map { |activity| activity[:end] }.max || 0

        create_block parent, :open, nil, attrs.merge({
          'role' => 'gantt-diagram',
          'gantt-data' => {
            'activities' => computed,
            'period' => period,
            'total-units' => total_units,
          }
        })
      end

      def parse_activity(line)
        match = line.match(/\A([^\s,]+)\s*,\s*"([^"]+)"(?:\s*,\s*(.+))?\z/)
        return nil unless match

        id = match[1]
        label = match[2].strip
        extras = match[3].to_s.split(",").map(&:strip)

        duration = nil
        dependencies = []

        extras.each do |extra|
          if extra =~ /\Aduration\s*=\s*(\d+)\z/
            duration = Regexp.last_match(1).to_i
          elsif extra =~ /\Adependencies\s*=\s*(.+)\z/
            dependencies = Regexp.last_match(1)
              .split(/[\s,;]+/)
              .map(&:strip)
              .reject(&:empty?)
          end
        end

        {
          id: id,
          label: label,
          duration: duration,
          dependencies: dependencies
        }
      end

      def compute_schedule(activities)
        resolved = {}
        pending = activities.map(&:dup)
        max_passes = pending.size * 2

        max_passes.times do
          progressed = false

          pending.delete_if do |activity|
            next false if activity[:is_group]

            deps = activity[:dependencies]
            deps_ends = deps.map { |dep| resolved[dep] && resolved[dep][:end] }.compact

            next false unless deps_ends.size == deps.size

            start_at = deps_ends.max || 0
            activity[:start] = start_at
            duration = activity[:is_milestone] ? 0 : activity[:duration]
            activity[:end] = start_at + duration
            resolved[activity[:id]] = activity
            progressed = true
            true
          end

          break unless progressed
        end

        pending.each do |activity|
          if activity[:is_group]
            activity[:start] = 0
            activity[:end] = 0
          elsif activity[:is_milestone]
            activity[:start] = 0
            activity[:end] = 0
          else
            activity[:start] = 0
            activity[:end] = activity[:duration]
          end
          resolved[activity[:id]] = activity
        end

        activities.map { |activity| resolved[activity[:id]] }
      end

      def escape_xml(text)
        text.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub("\"", "&quot;")
      end

      def apply_grouping(entries)
        grouped = []
        current_group_level = 0
        base_indent_level = 0
        indent_levels = []
        entries.each_with_index do |entry, index|
          activity = entry[:activity]
          next unless activity

          indent_level = entry[:indent].to_i
          base_indent_level = indent_level if base_indent_level == 0
          if indent_level > base_indent_level
            current_group_level = current_group_level + 1
            indent_levels << base_indent_level
            base_indent_level = indent_level
          else
            while indent_level < base_indent_level && current_group_level>0
              current_group_level = current_group_level - 1
              base_indent_level = indent_levels.pop
            end
          end
          activity[:indent_level] = current_group_level
          activity[:is_group] = false
          activity[:is_milestone] = activity[:duration].nil?
          grouped << activity

          next_entry = entries[index + 1]
          next unless next_entry && next_entry[:indent].to_i > indent_level
          activity[:is_group] = true
          activity[:is_milestone] = false
        end
        grouped
      end
    end

    class GanttBlockConverter < (Asciidoctor::Converter.for 'pdf')
      include Asciidoctor::Logging

      register_for 'pdf'

      def convert_open node
        if node.role == 'gantt-diagram'
          data = node.attr('gantt-data')
          document = node.document

          target = node.attr("target")
          target = "gantt-#{SecureRandom.hex(4)}.svg" if target.nil? || target.strip.empty?
          target = normalize_target(target)

          images_outdir = document.attr("imagesoutdir") || document.attr("imagesdir") || "."
          docdir = document.attr("docdir") || Dir.pwd
          images_outdir = File.expand_path(images_outdir, docdir) unless Pathname.new(images_outdir).absolute?

          output_path = if Pathname.new(target).absolute?
                          target
                        else
                          File.join(images_outdir, target)
                        end

          FileUtils.mkdir_p(File.dirname(output_path))
          svg = render_svg(document, data["activities"], data["total-units"], data["period"])
          File.write(output_path, svg)

          render_image = ::Asciidoctor::Block.new(
            node.parent,
            :image,
            source: nil,
            attributes: {
              'target' => output_path,
              'alt' => 'Gantt chart'
            }
          )

          convert_image render_image

        else
          super
        end
      end

      def normalize_target(target)
        normalized = target.strip
        if normalized =~ /\.[^.]+\z/
          normalized = normalized.sub(/\.[^.]+\z/, ".svg")
        else
          normalized = "#{normalized}.svg"
        end
        normalized
      end

      def render_svg(document, activities, total_units, period)
        font_family = get_setting(document, "gantt-font-family", :gantt_font_family,  document.attr("base-font-family"))
        font_size = get_setting(document, "gantt-font-size", :gantt_font_size, 12).to_i
        cell_width = get_setting(document, "gantt-cell-width", :gantt_cell_width, 28).to_i
        row_height = get_setting(document, "gantt-row-height", :gantt_row_height, 26).to_i
        header_height = get_setting(document, "gantt-header-height", :gantt_header_height, 28).to_i
        text_color = get_setting(document, "gantt-text-color", :gantt_text_color, "#222222")
        grid_color = get_setting(document, "gantt-grid-color", :gantt_grid_color, "#d8d8d8")
        bar_color = get_setting(document, "gantt-bar-color", :gantt_bar_color, "#4b8bbf")
        marker_color = get_setting(document, "gantt-marker-color", :gantt_marker_color, "#000000")
        header_fg = get_setting(document, "gantt-header-fg", :gantt_header_fg, "#ffffff")
        header_bg = get_setting(document, "gantt-header-bg", :gantt_header_bg, "#f5f5f5")

        label_texts = activities.map { |activity| "#{activity[:id]}. #{activity[:label]}" }
        label_max = label_texts.map(&:length).max || 10
        label_col_width = [160, (label_max * (font_size * 0.6) + 24).to_i].max

        left_padding = 12
        top_padding = 12
        right_padding = 12
        bottom_padding = 12

        total_units = [total_units, 1].max
        period_label = case period.to_s.downcase
                       when "week" then "W"
                       when "day" then "D"
                       when "month" then "M"
                       else period.to_s[0].to_s.upcase
                       end
        period_cell_padding = 6
        max_period_label_length = period_label.length + total_units.to_s.length
        min_cell_width = (max_period_label_length * (font_size * 0.7) + (period_cell_padding * 2)).to_i
        cell_width = [cell_width, min_cell_width].max

        grid_width = (total_units+1) * cell_width
        width = left_padding + label_col_width + grid_width + right_padding

        indent_width = 14
        separator_height = 10
        rows = build_rows(activities, row_height, separator_height)
        rows_height = rows.sum { |row| row[:height] }
        height = top_padding + header_height + rows_height + bottom_padding

        bar_height = (row_height * 0.55).to_i
        marker_width = [6, (bar_height * 0.8).to_i].max

        svg_lines = []
        svg_lines << "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"#{width}\" height=\"#{height}\" viewBox=\"0 0 #{width} #{height}\">"
        svg_lines << "  <rect x=\"0\" y=\"0\" width=\"#{width}\" height=\"#{height}\" fill=\"white\"/>"
        svg_lines << "  <rect x=\"#{left_padding}\" y=\"#{top_padding}\" width=\"#{label_col_width + grid_width}\" height=\"#{header_height}\" fill=\"#{header_bg}\"/>"

        header_y = top_padding + (header_height / 2) + (font_size / 2) - 2
        svg_lines << "  <text x=\"#{left_padding + 4}\" y=\"#{header_y}\" font-family=\"#{font_family}\" font-size=\"#{font_size}\" font-weight=\"700\" fill=\"#{header_fg}\">Activity</text>"

        total_units.times do |idx|
          label = "#{period_label}#{idx + 1}"
          x = left_padding + label_col_width + (idx * cell_width) + (cell_width)
          svg_lines << "  <text x=\"#{x}\" y=\"#{header_y}\" text-anchor=\"middle\" font-family=\"#{font_family}\" font-size=\"#{font_size}\" font-weight=\"700\" fill=\"#{header_fg}\">#{escape_xml(label)}</text>"
        end

        grid_top = top_padding + header_height
        grid_bottom = height - bottom_padding

        svg_lines << "  <line x1=\"#{left_padding + label_col_width}\" y1=\"#{top_padding}\" x2=\"#{left_padding + label_col_width}\" y2=\"#{grid_bottom}\" stroke=\"#{grid_color}\"/>"

        (1..total_units).each do |idx|
          next unless (idx % 5).zero?

          x = left_padding + label_col_width + (idx * cell_width) + cell_width/2
          svg_lines << "  <line x1=\"#{x}\" y1=\"#{top_padding}\" x2=\"#{x}\" y2=\"#{grid_bottom}\" stroke=\"#{grid_color}\"/>"
        end

        current_y = grid_top
        rows.each_with_index do |row, index|
          row_y = current_y
          row_height = row[:height]
          current_y += row_height

          if row[:type] == :separator
            line_y = row_y + (row_height / 2.0)
            svg_lines << "  <line x1=\"#{left_padding}\" y1=\"#{line_y}\" x2=\"#{left_padding + label_col_width + grid_width}\" y2=\"#{line_y}\" stroke=\"#{grid_color}\"/>"
            next
          end

          activity = row[:activity]
          label = "#{activity[:id]}. #{activity[:label]}"
          label_x = left_padding + 4 + (activity[:indent_level].to_i * indent_width)
          text_y = row_y + (row_height / 2) + (font_size / 2) - 2
          font_weight = activity[:is_group] ? "bold" : "normal"
          svg_lines << "  <text x=\"#{label_x}\" y=\"#{text_y}\" font-family=\"#{font_family}\" font-size=\"#{font_size}\" font-weight=\"#{font_weight}\" fill=\"#{text_color}\">#{escape_xml(label)}</text>"

          next_row = rows[index + 1]

          next if activity[:is_group]

          bar_y = row_y + ((row_height - bar_height) / 2)
          bar_center_y = bar_y + (bar_height / 2.0)

          if activity[:is_milestone]
            milestone_x = left_padding + label_col_width + (activity[:start] * cell_width) + cell_width/2
            milestone_marker(svg_lines,milestone_x, bar_y, bar_height, marker_color)
            next
          end

          start_x = left_padding + label_col_width + (activity[:start] * cell_width) + cell_width/2
          end_x = start_x + (activity[:duration] * cell_width)

          task_bar(svg_lines, start_x, bar_y, end_x-start_x, bar_height, bar_color, marker_color)
        end

        svg_lines << "</svg>"
        svg_lines.join("\n")
      end

      def get_setting(document, attr_name, theme_name, default)
        if document.attr(attr_name)
          return document.attr(attr_name)
        end

        if theme[theme_name]
          if default[0] == '#'
            return '#' + theme[theme_name]
          else
            return theme[theme_name]
          end
        end
        default
      end

      def build_rows(activities, row_height, separator_height)
        rows = []
        current_group = nil

        activities.each_with_index do |activity, index|
          rows << {type: :activity, activity: activity, height: row_height}

          if activity[:is_group]
            current_group = activity
            next
          end

          next_activity = activities[index + 1]
          if current_group && (next_activity.nil? || next_activity[:indent_level].to_i.zero?)
            rows << {type: :separator, height: separator_height}
            current_group = nil
          end
        end

        rows
      end

      def task_bar(svg_lines, start_x, bar_y, width, bar_height, bar_color, marker_color)

          marker_width = [6, (bar_height * 0.8).to_i].max
          marker_height = [8, (bar_height * 0.9).to_i].max
          marker_tip = [3, (marker_height * 0.35).to_i].max

          svg_lines << "  <rect x=\"#{start_x}\" y=\"#{bar_y}\" width=\"#{width}\" height=\"#{bar_height}\" fill=\"#{bar_color}\"/>"
          svg_lines << "  <polygon points=\"#{marker_points(start_x, bar_y, marker_width, marker_height, marker_tip)}\" fill=\"#{marker_color}\"/>"
          svg_lines << "  <polygon points=\"#{marker_points(start_x + width, bar_y, marker_width, marker_height, marker_tip)}\" fill=\"#{marker_color}\"/>"
      end

      def milestone_marker(svg_lines, milestone_x, bar_y, bar_height, marker_color)
          bar_center_y = bar_y + bar_height/2
          marker_width = [6, (bar_height * 0.8).to_i].max

          svg_lines << "  <polygon points=\"#{diamond_points(milestone_x, bar_center_y, marker_width)}\" fill=\"#{marker_color}\"/>"
      end

      def marker_points(center_x, top_y, width, height, tip_height)
        half = width / 2.0
        tip_y = top_y + height
        base_y = tip_y - tip_height
        left_x = center_x - half
        right_x = center_x + half

        "#{left_x},#{top_y} #{right_x},#{top_y} #{right_x},#{base_y} #{center_x},#{tip_y} #{left_x},#{base_y}"
      end

      def diamond_points(center_x, center_y, width)
        half = width / 2.0
        left_x = center_x - half
        right_x = center_x + half
        top_y = center_y - half
        bottom_y = center_y + half

        "#{center_x},#{top_y} #{right_x},#{center_y} #{center_x},#{bottom_y} #{left_x},#{center_y}"
      end
    end
  end
end

Asciidoctor::Extensions.register do
  block PresentationUtils::GanttDiagram::GanttBlockProcessor
end
