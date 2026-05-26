require 'asciidoctor'
require 'asciidoctor/extensions'
require 'asciidoctor-pdf'
require 'fileutils'
require 'pathname'
require 'securerandom'

module PresentationUtils
  module CustomDiagram
    class Parser
      def parse(content_or_lines)
        relevant_lines = Array(content_or_lines)
                         .flat_map { |item| item.to_s.split(/\r?\n/) }
                         .map(&:strip)
                         .reject(&:empty?)

        type = relevant_lines.shift.to_s
        {
          'type' => type,
          'members' => type == 'radial-team' ? parse_radial_team_members(relevant_lines) : []
        }
      end

      private

      def parse_radial_team_members(lines)
        lines.filter_map do |line|
          name, role = line.split(',', 2).map { |part| part.to_s.strip }
          next if name.to_s.empty? || role.to_s.empty?

          { 'name' => name, 'role' => role }
        end
      end
    end

    class CustomDiagramBlockProcessor < Asciidoctor::Extensions::BlockProcessor
      use_dsl
      named :'custom-diagram'
      on_context :listing
      parse_content_as :raw

      def process(parent, reader, attrs)
        data = Parser.new.parse(reader.lines)

        create_block parent, :open, nil, attrs.merge({
                                                       'role' => 'custom-diagram',
                                                       'custom-diagram-data' => data
                                                     })
      end
    end

    class CustomDiagramBlockConverter < (Asciidoctor::Converter.for 'pdf')
      register_for 'pdf'

      def convert_open(node)
        return super unless node.role == 'custom-diagram'

        data = node.attr('custom-diagram-data') || {}
        target = node.attr('target')
        target = "custom-diagram-#{SecureRandom.hex(4)}.svg" if target.nil? || target.strip.empty?
        target = normalize_target(target)

        output_path = resolve_output_path(node.document, target)
        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, render_svg(node.document, data))

        render_image = ::Asciidoctor::Block.new(
          node.parent,
          :image,
          source: nil,
          attributes: {
            'target' => output_path,
            'alt' => 'Custom diagram'
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

      def render_svg(document, data)
        return render_radial_team_svg(document, data['members'] || []) if data['type'] == 'radial-team'

        render_unknown_svg(data['type'])
      end

      def render_radial_team_svg(document, members)
        settings = radial_team_settings(document)
        layout = radial_team_layout(members, settings)
        lines = []
        lines << "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"#{layout[:width]}\" height=\"#{layout[:height]}\" viewBox=\"0 0 #{layout[:width]} #{layout[:height]}\">"
        lines << "  <rect x=\"0\" y=\"0\" width=\"#{layout[:width]}\" height=\"#{layout[:height]}\" fill=\"#{settings[:background_color]}\"/>"
        lines << "  <rect x=\"#{layout[:center_x]}\" y=\"#{layout[:center_y]}\" width=\"#{layout[:center_width]}\" height=\"#{layout[:center_height]}\" rx=\"32\" fill=\"#{settings[:center_fill]}\" stroke=\"#{settings[:center_stroke]}\" stroke-width=\"2\"/>"
        lines << "  <text x=\"#{layout[:center_x] + (layout[:center_width] / 2)}\" y=\"#{layout[:center_y] + 52}\" text-anchor=\"middle\" font-family=\"#{settings[:font_family]}\" font-size=\"#{settings[:center_font_size]}\" font-weight=\"700\" fill=\"#{settings[:center_text_color]}\">Team</text>"

        layout[:members].each do |member|
          lines << "  <line x1=\"#{member[:connector_start_x]}\" y1=\"#{member[:connector_y]}\" x2=\"#{member[:connector_end_x]}\" y2=\"#{member[:connector_y]}\" stroke=\"#{settings[:connector_color]}\" stroke-width=\"2\"/>"
        end

        layout[:members].each do |member|
          lines << "  <rect x=\"#{member[:x]}\" y=\"#{member[:y]}\" width=\"#{layout[:member_width]}\" height=\"#{layout[:member_height]}\" rx=\"22\" fill=\"#{member[:fill]}\" stroke=\"#{settings[:member_stroke]}\" stroke-width=\"2\"/>"
          lines << "  <text x=\"#{member[:x] + (layout[:member_width] / 2)}\" y=\"#{member[:y] + 28}\" text-anchor=\"middle\" font-family=\"#{settings[:font_family]}\" font-size=\"#{settings[:member_name_font_size]}\" font-weight=\"700\" fill=\"#{settings[:member_text_color]}\">#{escape_xml(member[:name])}</text>"
          lines << "  <text x=\"#{member[:x] + (layout[:member_width] / 2)}\" y=\"#{member[:y] + 48}\" text-anchor=\"middle\" font-family=\"#{settings[:font_family]}\" font-size=\"#{settings[:member_role_font_size]}\" fill=\"#{settings[:member_role_color]}\">#{escape_xml(member[:role])}</text>"
        end

        lines << '</svg>'
        lines.join("\n")
      end

      def render_unknown_svg(type)
        label = "Unsupported custom diagram: #{type}"
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"480\" height=\"96\" viewBox=\"0 0 480 96\"><rect width=\"480\" height=\"96\" fill=\"#ffffff\"/><text x=\"24\" y=\"54\" font-family=\"Arial, sans-serif\" font-size=\"16\" fill=\"#991b1b\">#{escape_xml(label)}</text></svg>"
      end

      def radial_team_settings(document)
        {
          background_color: get_setting(document, 'custom-diagram-background-color', :custom_diagram_background_color,
                                        '#ffffff'),
          font_family: get_setting(document, 'custom-diagram-font-family', :custom_diagram_font_family,
                                   document.attr('base-font-family') || 'Arial, sans-serif'),
          center_font_size: get_setting(document, 'custom-diagram-center-font-size', :custom_diagram_center_font_size,
                                        24).to_i,
          member_name_font_size: get_setting(document, 'custom-diagram-member-name-font-size',
                                             :custom_diagram_member_name_font_size, 16).to_i,
          member_role_font_size: get_setting(document, 'custom-diagram-member-role-font-size',
                                             :custom_diagram_member_role_font_size, 12).to_i,
          center_fill: get_setting(document, 'custom-diagram-center-fill', :custom_diagram_center_fill, '#eef4f8'),
          center_stroke: get_setting(document, 'custom-diagram-center-stroke', :custom_diagram_center_stroke,
                                     '#6f8798'),
          center_text_color: get_setting(document, 'custom-diagram-center-text-color',
                                         :custom_diagram_center_text_color, '#263743'),
          connector_color: get_setting(document, 'custom-diagram-connector-color', :custom_diagram_connector_color,
                                       '#8aa0af'),
          member_stroke: get_setting(document, 'custom-diagram-member-stroke', :custom_diagram_member_stroke,
                                     '#6f8798'),
          member_text_color: get_setting(document, 'custom-diagram-member-text-color',
                                         :custom_diagram_member_text_color, '#ffffff'),
          member_role_color: get_setting(document, 'custom-diagram-member-role-color',
                                         :custom_diagram_member_role_color, '#ffffff'),
          member_palette: parse_palette(get_setting(document, 'custom-diagram-member-palette',
                                                    :custom_diagram_member_palette, '#7890a1,#8aa0af,#6f8798,#9badba,#607888,#a5b5bf'))
        }
      end

      def get_setting(document, attr_name, theme_name, default)
        attr_value = document.attr(attr_name)
        return attr_value unless attr_value.nil? || attr_value.to_s.empty?

        theme_value = theme[theme_name] if respond_to?(:theme) && theme
        return normalize_color_value(theme_value, default) unless theme_value.nil?

        default
      end

      def normalize_color_value(value, default)
        return value unless default.to_s.start_with?('#')

        value.to_s.start_with?('#') ? value : "##{value}"
      end

      def parse_palette(value)
        palette = value.to_s.split(',').map(&:strip).reject(&:empty?)
        palette.empty? ? ['#7890a1'] : palette
      end

      def radial_team_layout(members, settings)
        width = 820
        center_width = 260
        center_height = 86
        member_width = 190
        member_height = 66
        row_gap = 24
        padding = 24
        side_count = [(members.length + 1) / 2, members.length / 2].max
        side_height = side_count.zero? ? member_height : (side_count * member_height) + ((side_count - 1) * row_gap)
        height = [420, side_height + (padding * 2)].max
        center_x = (width - center_width) / 2
        center_y = (height - center_height) / 2
        palette = settings[:member_palette]

        left_members = []
        right_members = []
        members.each_with_index do |member, index|
          (index.even? ? left_members : right_members) << [member, index]
        end

        placed = []
        [[left_members, padding, center_x, :left],
         [right_members, width - padding - member_width, center_x + center_width,
          :right]].each do |column_members, x, center_edge_x, side|
          column_height = column_members.length.zero? ? 0 : (column_members.length * member_height) + ((column_members.length - 1) * row_gap)
          y = (height - column_height) / 2
          column_members.each_with_index do |member, index|
            raw_member, original_index = member
            connector_start_x = side == :left ? x + member_width : x
            placed << {
              x: x,
              y: y + (index * (member_height + row_gap)),
              connector_y: y + (index * (member_height + row_gap)) + (member_height / 2),
              connector_start_x: connector_start_x,
              connector_end_x: center_edge_x,
              name: raw_member['name'],
              role: raw_member['role'],
              fill: palette[original_index % palette.length]
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
    end
  end
end

Asciidoctor::Extensions.register do
  block PresentationUtils::CustomDiagram::CustomDiagramBlockProcessor
end
