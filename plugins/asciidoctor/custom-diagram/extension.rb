require 'asciidoctor'
require 'asciidoctor/extensions'
require 'asciidoctor-pdf'
require 'fileutils'
require 'pathname'
require 'securerandom'

require_relative 'radial_diagram'
require_relative 'dispatcher'

module PresentationUtils
  module CustomDiagram
    class Parser
      def parse(content_or_lines)
        relevant_lines = Array(content_or_lines)
                         .flat_map { |item| item.to_s.split(/\r?\n/) }
                         .map(&:strip)
                         .reject(&:empty?)

        type = relevant_lines.shift.to_s
        dispatcher.parse(type, relevant_lines)
      end

      private

      def dispatcher
        @dispatcher ||= Dispatcher.new
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
        File.write(output_path, render_custom_diagram_svg(node.document, data))

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

      def render_custom_diagram_svg(document, data)
        dispatcher.render(document, data, theme: current_theme) || render_unknown_svg(data['type'])
      end

      def current_theme
        respond_to?(:theme) ? theme : nil
      end

      def render_unknown_svg(type)
        label = "Unsupported custom diagram: #{type}"
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"480\" height=\"96\" viewBox=\"0 0 480 96\"><rect width=\"480\" height=\"96\" fill=\"#ffffff\"/><text x=\"24\" y=\"54\" font-family=\"Arial, sans-serif\" font-size=\"16\" fill=\"#991b1b\">#{escape_xml(label)}</text></svg>"
      end

      def escape_xml(text)
        text.to_s
            .gsub('&', '&amp;')
            .gsub('<', '&lt;')
            .gsub('>', '&gt;')
            .gsub('"', '&quot;')
      end

      private

      def dispatcher
        @dispatcher ||= Dispatcher.new
      end
    end
  end
end

Asciidoctor::Extensions.register do
  block PresentationUtils::CustomDiagram::CustomDiagramBlockProcessor
end
