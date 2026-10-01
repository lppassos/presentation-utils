require 'asciidoctor'
require 'asciidoctor/extensions'
require 'pathname'
require 'yaml'

module PresentationUtils
  module MermaidTheme
    # Asciidoctor Diagram resolves Mermaid's config attribute relative to the
    # source document. This preprocessor instead resolves the config declared
    # by the selected PDF theme relative to that theme's YAML file.
    class ThemeConfigPreprocessor < Asciidoctor::Extensions::Preprocessor
      def process(document, reader)
        return reader if present?(document.attr('mermaid-config'))

        theme_file = resolve_theme_file(document)
        return reader unless theme_file

        config = mermaid_config(theme_file)
        return reader unless present?(config)

        config_file = resolve_config_file(config, theme_file)
        raise "Mermaid config declared by PDF theme not found: #{config_file}" unless File.file?(config_file)

        document.set_attr('mermaid-config', config_file)
        reader
      end

      private

      def resolve_theme_file(document)
        theme = document.attr('pdf-theme')
        themes_dir = document.attr('pdf-themesdir')
        return nil unless present?(theme) && present?(themes_dir)

        theme_path = Pathname.new(theme)
        candidates = if theme_path.absolute?
                       [theme]
                     else
                       [File.join(themes_dir, theme)]
                     end
        candidates.concat(candidates.map { |candidate| "#{candidate}.yml" unless candidate.end_with?('.yml') }.compact)
        candidates.find { |candidate| File.file?(candidate) }
      end

      def mermaid_config(theme_file)
        theme = YAML.safe_load(File.read(theme_file), permitted_classes: [], aliases: true)
        return nil unless theme.is_a?(Hash)

        mermaid = theme['mermaid'] || theme[:mermaid]
        return mermaid['config'] || mermaid[:config] if mermaid.is_a?(Hash)

        theme['mermaid-config'] || theme[:'mermaid-config'] || theme['mermaid_config'] || theme[:mermaid_config]
      rescue Psych::SyntaxError => e
        raise "Invalid PDF theme YAML #{theme_file}: #{e.message.lines.first.strip}"
      end

      def resolve_config_file(config, theme_file)
        path = Pathname.new(config.to_s)
        return path.to_s if path.absolute?

        File.expand_path(path.to_s, File.dirname(theme_file))
      end

      def present?(value)
        !value.nil? && !value.to_s.strip.empty?
      end
    end
  end
end

Asciidoctor::Extensions.register do
  preprocessor PresentationUtils::MermaidTheme::ThemeConfigPreprocessor
end
