require 'asciidoctor'
require 'asciidoctor/extensions'
require 'fileutils'
require 'open3'

module PresentationUtils
  module DrawioImage
    class DrawioImageProcessor < Asciidoctor::Extensions::TreeProcessor
      include Asciidoctor::Logging

      def process(_document)
        nil
      end
    end
  end
end

Asciidoctor::Extensions.register do
  treeprocessor PresentationUtils::DrawioImage::DrawioImageProcessor
end
