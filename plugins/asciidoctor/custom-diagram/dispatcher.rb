module PresentationUtils
  module CustomDiagram
    class Dispatcher
      def initialize(diagrams = [RadialDiagram.new])
        @diagrams_by_type = diagrams.to_h { |diagram| [diagram.class.type, diagram] }
      end

      def parse(type, lines)
        diagram = @diagrams_by_type[type]
        return { 'type' => type } unless diagram

        diagram.parse(lines).merge('type' => type)
      end

      def render(document, data, theme: nil)
        diagram = @diagrams_by_type[data['type']]
        return nil unless diagram

        diagram.render(document, data, theme: theme)
      end
    end
  end
end
