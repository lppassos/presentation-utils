require 'asciidoctor'
require 'asciidoctor/extensions'
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
      named :custom_diagram
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
        File.write(output_path, render_svg(data))

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

      def render_svg(data)
        return render_radial_team_svg(data['members'] || []) if data['type'] == 'radial-team'

        render_unknown_svg(data['type'])
      end

      def render_radial_team_svg(members)
        layout = radial_team_layout(members)
        lines = []
        lines << "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"#{layout[:width]}\" height=\"#{layout[:height]}\" viewBox=\"0 0 #{layout[:width]} #{layout[:height]}\">"
        lines << "  <rect x=\"0\" y=\"0\" width=\"#{layout[:width]}\" height=\"#{layout[:height]}\" fill=\"white\"/>"
        lines << "  <rect x=\"#{layout[:center_x]}\" y=\"#{layout[:center_y]}\" width=\"#{layout[:center_width]}\" height=\"#{layout[:center_height]}\" rx=\"32\" fill=\"#eef4f8\" stroke=\"#6f8798\" stroke-width=\"2\"/>"
        lines << "  <text x=\"#{layout[:center_x] + (layout[:center_width] / 2)}\" y=\"#{layout[:center_y] + 52}\" text-anchor=\"middle\" font-family=\"Arial, sans-serif\" font-size=\"24\" font-weight=\"700\" fill=\"#263743\">Team</text>"

        layout[:members].each do |member|
          lines << "  <line x1=\"#{member[:connector_start_x]}\" y1=\"#{member[:connector_y]}\" x2=\"#{member[:connector_end_x]}\" y2=\"#{member[:connector_y]}\" stroke=\"#8aa0af\" stroke-width=\"2\"/>"
        end

        layout[:members].each do |member|
          lines << "  <rect x=\"#{member[:x]}\" y=\"#{member[:y]}\" width=\"#{layout[:member_width]}\" height=\"#{layout[:member_height]}\" rx=\"22\" fill=\"#{member[:fill]}\" stroke=\"#6f8798\" stroke-width=\"2\"/>"
          lines << "  <text x=\"#{member[:x] + (layout[:member_width] / 2)}\" y=\"#{member[:y] + 28}\" text-anchor=\"middle\" font-family=\"Arial, sans-serif\" font-size=\"16\" font-weight=\"700\" fill=\"#ffffff\">#{escape_xml(member[:name])}</text>"
          lines << "  <text x=\"#{member[:x] + (layout[:member_width] / 2)}\" y=\"#{member[:y] + 48}\" text-anchor=\"middle\" font-family=\"Arial, sans-serif\" font-size=\"12\" fill=\"#ffffff\">#{escape_xml(member[:role])}</text>"
        end

        lines << '</svg>'
        lines.join("\n")
      end

      def render_unknown_svg(type)
        label = "Unsupported custom diagram: #{type}"
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"480\" height=\"96\" viewBox=\"0 0 480 96\"><rect width=\"480\" height=\"96\" fill=\"#ffffff\"/><text x=\"24\" y=\"54\" font-family=\"Arial, sans-serif\" font-size=\"16\" fill=\"#991b1b\">#{escape_xml(label)}</text></svg>"
      end

      def radial_team_layout(members)
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
        palette = ['#7890a1', '#8aa0af', '#6f8798', '#9badba', '#607888', '#a5b5bf']

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
