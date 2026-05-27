module PresentationUtils
  module CustomDiagram
    class RadialDiagram
      TYPE = 'radial'.freeze

      def self.type
        TYPE
      end

      def parse(lines)
        title = 'Team'
        if lines[0].to_s.strip.match?(/^title\s+.+$/i)
          title = lines[0].to_s.strip.sub(/^title\s+/i, '').strip
          lines = lines.drop(1)
        end

        {
          'title' => title,
          'members' => lines.filter_map do |line|
            name, role = line.split(',', 2).map { |part| part.to_s.strip }
            next if name.to_s.empty? || role.to_s.empty?

            { 'name' => name, 'role' => role }
          end
        }
      end

      def render(document, data, theme: nil)
        settings = settings(document, theme)
        layout = layout(data['members'] || [], settings)
        lines = []
        lines << '<svg xmlns="http://www.w3.org/2000/svg"'
        lines << "     width=\"#{layout[:width]}\" height=\"#{layout[:height]}\""
        lines << "     viewBox=\"0 0 #{layout[:width]} #{layout[:height]}\">"
        lines << "  <rect x=\"0\" y=\"0\" width=\"#{layout[:width]}\" height=\"#{layout[:height]}\" fill=\"#{settings[:background_color]}\"/>"

        lines << render_center(layout[:center_x], layout[:center_y], layout[:center_width],
                               layout[:center_height], settings[:center_fill], settings[:center_stroke],
                               data['title'] || 'Team', settings[:center_text_color], settings[:font_family],
                               settings[:center_font_size])

        layout[:members].each do |member|
          lines << render_connector(member[:connector_start_x], member[:connector_start_y],
                                    member[:connector_end_x], member[:connector_end_y],
                                    settings[:connector_color])
        end

        layout[:members].each do |member|
          lines << "  <rect x=\"#{member[:x]}\" y=\"#{member[:y]}\" width=\"#{layout[:member_width]}\" height=\"#{layout[:member_height]}\" rx=\"22\" fill=\"#{settings[:member_fill]}\" stroke=\"#{settings[:member_stroke]}\" stroke-width=\"2\"/>"
          lines << "  <text x=\"#{member[:x] + (layout[:member_width] / 2)}\" y=\"#{member[:y] + 28}\" text-anchor=\"middle\" font-family=\"#{settings[:font_family]}\" font-size=\"#{settings[:member_name_font_size]}\" font-weight=\"700\" fill=\"#{settings[:member_text_color]}\">#{escape_xml(member[:name])}</text>"
          lines << "  <text x=\"#{member[:x] + (layout[:member_width] / 2)}\" y=\"#{member[:y] + 48}\" text-anchor=\"middle\" font-family=\"#{settings[:font_family]}\" font-size=\"#{settings[:member_role_font_size]}\" fill=\"#{settings[:member_role_color]}\">#{escape_xml(member[:role])}</text>"
        end

        lines << '</svg>'
        lines.join("\n")
      end

      private

      def render_center(x, y, width, height, fill, stroke, text, text_color, text_font, text_size)
        middle_x = x + width / 2
        outer_w = width / 2 - 80
        [
          "<rect x=\"#{x}\" y=\"#{y}\" width=\"#{width}\" height=\"#{height}\"
                rx=\"#{height / 2}\" fill=\"#{fill}\" stroke=\"#{stroke}\" stroke-width=\"2\"/>",
          "<path d=\"M #{middle_x + 45} #{y - 10} h #{outer_w} a #{height / 2} #{height / 2} 0 0 1 0 #{height + 20} h -#{outer_w}\" fill=\"none\" stroke=\"#{stroke}\" stroke-width=\"4\"/>",
          "<path d=\"M #{middle_x - 45} #{y - 10} h -#{outer_w} a #{height / 2} #{height / 2} 0 0 0 0 #{height + 20} h #{outer_w}\" fill=\"none\" stroke=\"#{stroke}\" stroke-width=\"4\"/>",
          "<text x=\"#{x + (width / 2)}\" y=\"#{y + 41}\" text-anchor=\"middle\" font-family=\"#{text_font}\" font-size=\"#{text_size}\" font-weight=\"700\" fill=\"#{text_color}\">#{text}</text>"
        ].join("\n")
      end

      def render_connector(sx, sy, ex, ey, color)
        connector = connector_geometry(sx, sy, ex, ey)
        [
          "<circle cx=\"#{connector[:start_circle_x]}\" cy=\"#{connector[:start_circle_y]}\" r=\"#{connector[:radius]}\" fill=\"#{color}\" stroke=\"#{color}\" />",
          "<circle cx=\"#{connector[:end_circle_x]}\" cy=\"#{connector[:end_circle_y]}\" r=\"#{connector[:radius]}\" fill=\"#{color}\" stroke=\"#{color}\" />",
          "<path d=\"#{connector[:path]}\" fill=\"none\" stroke=\"#{color}\" stroke-width=\"2\" stroke-linecap=\"round\" />"
        ].join("\n")
      end

      def settings(document, theme)
        {
          background_color: get_setting(document, theme, 'custom-diagram-radial-background-color', :custom_diagram_radial_background_color,
                                        '#ffffff'),
          font_family: get_setting(document, theme, 'custom-diagram-radial-font-family', :custom_diagram_radial_font_family,
                                   document.attr('base-font-family') || 'Arial, sans-serif'),
          center_font_size: get_setting(document, theme, 'custom-diagram-radial-center-font-size', :custom_diagram_radial_center_font_size,
                                        24).to_i,
          member_name_font_size: get_setting(document, theme, 'custom-diagram-radial-member-name-font-size',
                                             :custom_diagram_radial_member_name_font_size, 16).to_i,
          member_role_font_size: get_setting(document, theme, 'custom-diagram-radial-member-role-font-size',
                                             :custom_diagram_radial_member_role_font_size, 12).to_i,
          center_fill: get_setting(document, theme, 'custom-diagram-radial-center-fill', :custom_diagram_radial_center_fill,
                                   '#eef4f8'),
          center_stroke: get_setting(document, theme, 'custom-diagram-radial-center-stroke', :custom_diagram_radial_center_stroke,
                                     '#6f8798'),
          center_text_color: get_setting(document, theme, 'custom-diagram-radial-center-text-color',
                                         :custom_diagram_radial_center_text_color, '#263743'),
          connector_color: get_setting(document, theme, 'custom-diagram-radial-connector-color', :custom_diagram_radial_connector_color,
                                       '#8aa0af'),
          member_fill: get_setting(document, theme, 'custom-diagram-radial-member-fill', :custom_diagram_radial_member_fill,
                                   '#7890a1'),
          member_stroke: get_setting(document, theme, 'custom-diagram-radial-member-stroke', :custom_diagram_radial_member_stroke,
                                     '#6f8798'),
          member_text_color: get_setting(document, theme, 'custom-diagram-radial-member-text-color',
                                         :custom_diagram_radial_member_text_color, '#ffffff'),
          member_role_color: get_setting(document, theme, 'custom-diagram-radial-member-role-color',
                                         :custom_diagram_radial_member_role_color, '#ffffff')
        }
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

      def layout(members, _settings)
        min_width = 820
        center_width = 260
        center_height = 66
        member_width = 190
        member_height = 66
        column_gap = 24
        center_gap = 52
        center_connector_span = 90
        padding = 24
        top_count = (members.length / 2.0).ceil
        bottom_count = members.length - top_count
        max_row_count = [top_count, bottom_count, 1].max
        row_width = (max_row_count * member_width) + ((max_row_count - 1) * column_gap)
        width = [min_width, row_width + (padding * 2)].max
        height = 420
        center_x = (width - center_width) / 2
        center_y = (height - center_height) / 2
        top_y = center_y - center_gap - member_height
        bottom_y = center_y + center_height + center_gap
        top_members = members.first(top_count).each_with_index.map { |member, index| [member, index] }
        bottom_members = members.drop(top_count).each_with_index.map { |member, index| [member, top_count + index] }

        placed = []
        [[top_members, top_y, center_y - 5, true],
         [bottom_members, bottom_y, center_y + center_height + 5,
          false]].each do |row_members, y, center_anchor_y, top_row|
          current_row_width = row_members.length.zero? ? 0 : (row_members.length * member_width) + ((row_members.length - 1) * column_gap)
          start_x = (width - current_row_width) / 2
          row_members.each_with_index do |member, index|
            raw_member, _original_index = member
            x = start_x + (index * (member_width + column_gap))
            placed << {
              x: x,
              y: y,
              connector_start_x: x + (member_width / 2),
              connector_start_y: top_row ? y + member_height + 5 : y - 5,
              connector_end_x: center_connector_x(center_x, center_width, center_connector_span, row_members.length,
                                                  index),
              connector_end_y: center_anchor_y,
              name: raw_member['name'],
              role: raw_member['role']
            }
          end
        end

        {
          width: width,
          height: height,
          center_x: center_x,
          center_y: center_y,
          center_width: center_width,
          center_height: center_height,
          member_width: member_width,
          member_height: member_height,
          members: placed.sort_by { |member| [member[:y], member[:x]] }
        }
      end

      def escape_xml(text)
        text.to_s
            .gsub('&', '&amp;')
            .gsub('<', '&lt;')
            .gsub('>', '&gt;')
            .gsub('"', '&quot;')
      end

      def center_connector_x(center_x, center_width, span, count, index)
        return center_x + (center_width / 2) if count <= 1

        start_x = center_x + ((center_width - span) / 2)
        start_x + ((span * (index + 1)) / (count + 1))
      end

      def connector_geometry(start_x, start_y, end_x, end_y)
        radius = 5
        mid_y = (start_y + end_y) / 2
        start_circle_y = start_y + sign(mid_y - start_y, end_y - start_y, 1) * radius
        end_circle_y = end_y + sign(mid_y - end_y, start_y - end_y, -1) * radius

        if start_x == end_x
          return {
            path: "M #{start_x} #{start_circle_y} L #{end_x} #{end_circle_y}",
            start_circle_x: start_x,
            start_circle_y: start_circle_y,
            end_circle_x: end_x,
            end_circle_y: end_circle_y,
            radius: radius
          }
        end

        path = rounded_orthogonal_path([
                                         [start_x, start_circle_y],
                                         [start_x, mid_y],
                                         [end_x, mid_y],
                                         [end_x, end_circle_y]
                                       ], 8)
        {
          path: path,
          start_circle_x: start_x,
          start_circle_y: start_circle_y,
          end_circle_x: end_x,
          end_circle_y: end_circle_y,
          radius: radius
        }
      end

      def rounded_orthogonal_path(points, corner_radius)
        path = "M #{points[0][0]} #{points[0][1]}"

        (1...(points.length - 1)).each do |index|
          previous = points[index - 1]
          current = points[index]
          nxt = points[index + 1]
          incoming_length = distance(previous, current)
          outgoing_length = distance(current, nxt)
          trim = [corner_radius, incoming_length / 2.0, outgoing_length / 2.0].min
          corner_start = move_toward(current, previous, trim)
          corner_end = move_toward(current, nxt, trim)
          path += " L #{corner_start[0]} #{corner_start[1]} Q #{current[0]} #{current[1]} #{corner_end[0]} #{corner_end[1]}"
        end

        last = points[-1]
        path + " L #{last[0]} #{last[1]}"
      end

      def move_toward(from, to, distance_amount)
        total_distance = distance(from, to)
        return [from[0], from[1]] if total_distance.zero?

        ratio = distance_amount.to_f / total_distance
        [from[0] + ((to[0] - from[0]) * ratio), from[1] + ((to[1] - from[1]) * ratio)]
      end

      def distance(point_a, point_b)
        (point_a[0] - point_b[0]).abs + (point_a[1] - point_b[1]).abs
      end

      def sign(*values)
        values.each do |value|
          return value <=> 0 unless value.to_f.zero?
        end

        0
      end
    end
  end
end
