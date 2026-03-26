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
        group_bars = "all";
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

          if stripped.start_with?("group-bars:")
            value = stripped.split(":", 2)[1].to_s.strip
            group_bars = value
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

        group_descendants = build_group_descendants(activities)

        computed = compute_schedule(activities, group_descendants)
        total_units = computed.map { |activity| activity[:end] }.max || 0.0

        create_block parent, :open, nil, attrs.merge({
          'role' => 'gantt-diagram',
          'gantt-data' => {
            'activities' => computed,
            'period' => period,
            'group-bars' => group_bars,
            'total-units' => total_units,
          }
        })
      end

      def build_group_descendants(activities)
        map = {}

        activities.each_with_index do |activity, idx|
          next unless activity[:is_group]

          group_level = activity[:indent_level].to_i
          leaf_ids = []

          j = idx + 1
          while j < activities.length && activities[j][:indent_level].to_i > group_level
            leaf_ids << activities[j][:id] unless activities[j][:is_group]
            j += 1
          end

          map[activity[:id]] = leaf_ids
        end

        map
      end

      def parse_activity(line)
        match = line.match(/\A([^\s,]+)\s*,\s*"([^"]+)"(?:\s*,\s*(.+))?\z/)
        return nil unless match

        id = match[1]
        label = match[2].strip
        extras = match[3].to_s.split(",").map(&:strip)

        duration = nil
        dependencies = []
        dependency_tokens = []
        not_before_slot = nil

        extras.each do |extra|
          if extra =~ /\Aduration\s*=\s*([0-9]*\.?[0-9]+)\z/
            duration = Regexp.last_match(1).to_f
          elsif extra =~ /\Adependencies\s*=\s*(.+)\z/
            dependencies = Regexp.last_match(1)
              .split(/[\s,;]+/)
              .map(&:strip)
              .reject(&:empty?)
            dependency_tokens = dependencies
              .map { |dep| parse_dependency_token(dep) }
              .compact
          elsif extra =~ /\AnotBefore\s*=\s*([0-9]*\.?[0-9]+)\z/
            not_before_slot = Regexp.last_match(1).to_f
            not_before_slot = 1.0 if not_before_slot < 1.0
          end
        end

        {
          id: id,
          label: label,
          duration: duration,
          dependencies: dependencies,
          dependency_tokens: dependency_tokens,
          not_before_slot: not_before_slot
        }
      end

      def parse_dependency_token(raw)
        token = raw.to_s.strip
        return nil if token.empty?

        match = token.match(/\A(ss|ff)(.+)\z/i)
        if match
          id = match[2].to_s.strip
          return nil if id.empty?
          return { type: match[1].upcase, id: id }
        end

        { type: "FS", id: token }
      end

      def compute_schedule(activities, group_descendants)
        resolved = {}
        pending = activities.map(&:dup)
        max_passes = pending.size * 2

        resolve_activity = lambda do |activity|
          deps = (activity[:dependency_tokens] || []).compact
          referenced = deps.map { |dep| dep[:id] }.compact
          resolved_referenced = referenced.select { |id| resolved[id] }
          return nil unless resolved_referenced.size == referenced.size

          not_before_start_at = activity[:not_before_slot] ? (activity[:not_before_slot].to_f - 1.0) : 0.0

          fs_ends = deps
            .select { |dep| dep[:type] == "FS" }
            .map { |dep| resolved[dep[:id]][:end].to_f }
          ss_starts = deps
            .select { |dep| dep[:type] == "SS" }
            .map { |dep| resolved[dep[:id]][:start].to_f }
          ff_ends = deps
            .select { |dep| dep[:type] == "FF" }
            .map { |dep| resolved[dep[:id]][:end].to_f }

          start_min = [
            not_before_start_at.to_f,
            (fs_ends.max || 0.0),
            (ss_starts.max || 0.0),
          ].max
          end_min = ff_ends.max || 0.0

          has_ss = !ss_starts.empty?
          has_ff = !ff_ends.empty?

          d = activity[:is_milestone] ? 0.0 : (activity[:duration] || 0.0).to_f

          if has_ss && has_ff
            activity[:start] = start_min
            activity[:end] = [end_min, activity[:start]].max
            activity[:duration] = [0.0, activity[:end] - activity[:start]].max
          elsif has_ff
            activity[:start] = [start_min, end_min - d].max
            activity[:end] = activity[:start] + d
          else
            activity[:start] = start_min
            activity[:end] = activity[:start] + d
          end

          activity
        end

        max_passes.times do
          progressed = false

          pending.delete_if do |activity|
            next false unless activity[:is_group]

            leaf_ids = (group_descendants && group_descendants[activity[:id]]) || []
            next false if leaf_ids.size > 0 && !leaf_ids.all? { |id| resolved[id] }

            activity[:is_milestone] = false
            activity[:duration] = 0.0

            if leaf_ids.size > 0
              starts = leaf_ids.map { |id| resolved[id][:start].to_f }
              ends = leaf_ids.map { |id| resolved[id][:end].to_f }
              activity[:start] = starts.min
              activity[:end] = ends.max
            else
              activity[:start] = 0.0
              activity[:end] = 0.0
            end
            activity[:duration] = [0.0, activity[:end] - activity[:start]].max

            resolved[activity[:id]] = activity
            progressed = true
            true
          end

          pending.delete_if do |activity|
            next false if activity[:is_group]

            next false unless resolve_activity.call(activity)

            resolved[activity[:id]] = activity
            progressed = true
            true
          end

          break unless progressed
        end

        pending.each do |activity|
          did_resolve = resolve_activity.call(activity)

          unless did_resolve
            if activity[:is_group]
              activity[:start] = 0.0
              activity[:end] = 0.0
              activity[:duration] = 0.0
              activity[:has_group_bar] = false
            elsif activity[:is_milestone]
              not_before_start_at = activity[:not_before_slot] ? (activity[:not_before_slot].to_f - 1.0) : 0.0
              activity[:start] = not_before_start_at
              activity[:end] = not_before_start_at
            else
              not_before_start_at = activity[:not_before_slot] ? (activity[:not_before_slot].to_f - 1.0) : 0.0
              activity[:start] = not_before_start_at
              activity[:end] = not_before_start_at + (activity[:duration] || 0.0)
            end
          end

          resolved[activity[:id]] = activity
        end

        ordered = activities.map { |activity| resolved[activity[:id]] }

        ordered.each do |activity|
          next unless activity[:is_group]
          leaf_ids = (group_descendants && group_descendants[activity[:id]]) || []
          activity[:has_group_bar] = leaf_ids.size > 1
        end

        ordered
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
          svg = render_svg(document, data["activities"], data["total-units"], data["period"], data["group-bars"])
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

      def render_svg(document, activities, total_units, period, group_bars)
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

        total_units = [total_units.to_f, 1.0].max
        columns = [total_units.ceil, 1].max
        period_label = case period.to_s.downcase
                       when "week" then "W"
                       when "day" then "D"
                       when "month" then "M"
                       else period.to_s[0].to_s.upcase
                       end
        period_cell_padding = 6
        max_period_label_length = period_label.length + columns.to_s.length
        min_cell_width = (max_period_label_length * (font_size * 0.7) + (period_cell_padding * 2)).to_i
        cell_width = [cell_width, min_cell_width].max

        grid_width = (columns + 1) * cell_width
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

        columns.times do |idx|
          label = "#{period_label}#{idx + 1}"
          x = left_padding + label_col_width + (idx * cell_width) + (cell_width)
          svg_lines << "  <text x=\"#{x}\" y=\"#{header_y}\" text-anchor=\"middle\" font-family=\"#{font_family}\" font-size=\"#{font_size}\" font-weight=\"700\" fill=\"#{header_fg}\">#{escape_xml(label)}</text>"
        end

        grid_top = top_padding + header_height
        grid_bottom = height - bottom_padding

        svg_lines << "  <line x1=\"#{left_padding + label_col_width}\" y1=\"#{top_padding}\" x2=\"#{left_padding + label_col_width}\" y2=\"#{grid_bottom}\" stroke=\"#{grid_color}\"/>"

        (1..columns).each do |idx|
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
          bar_y = row_y + ((row_height - bar_height) / 2)
          start_x = left_padding + label_col_width + (activity[:start] * cell_width) + cell_width/2

          if activity[:is_group]
            if (activity[:has_group_bar] && group_bars != "none") || group_bars =="all"
              group_bar_height = [2, (bar_height * 0.5).to_i].max

              width = (activity[:duration] * cell_width)

              group_bar(svg_lines, start_x, bar_y, width, group_bar_height, marker_color, marker_color)
            end
            next
          end


          if activity[:is_milestone]
            milestone_x = left_padding + label_col_width + (activity[:start] * cell_width) + cell_width/2
            milestone_marker(svg_lines,milestone_x, bar_y, bar_height, marker_color)
            next
          end

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

      def group_bar(svg_lines, start_x, bar_y, width, bar_height, bar_color, marker_color)
          marker_width = [6, (bar_height * 0.8).to_i].max
          marker_height = (bar_height * 1.5).to_i
          marker_tip = [3, (marker_height * 0.35).to_i].max

          svg_lines << "  <rect x=\"#{start_x}\" y=\"#{bar_y}\" width=\"#{width}\" height=\"#{bar_height}\" fill=\"#{bar_color}\"/>"
          svg_lines << "  <polygon points=\"#{marker_points(start_x, bar_y, marker_width, marker_height, marker_tip)}\" fill=\"#{marker_color}\"/>"
          svg_lines << "  <polygon points=\"#{marker_points(start_x + width, bar_y, marker_width, marker_height, marker_tip)}\" fill=\"#{marker_color}\"/>"
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
