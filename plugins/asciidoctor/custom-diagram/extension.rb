require 'asciidoctor'
require 'asciidoctor/extensions'

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
  end
end

Asciidoctor::Extensions.register do
  block PresentationUtils::CustomDiagram::CustomDiagramBlockProcessor
end
