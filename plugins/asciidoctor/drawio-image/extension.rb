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

      private

      # Resolves the absolute path of a .drawio source file.
      # The target is resolved relative to imagesdir (which itself is relative to docdir
      # when it is not an absolute path).
      def resolve_drawio_path(doc, target)
        docdir    = doc.attr('docdir', Dir.pwd).to_s
        imagesdir = doc.attr('imagesdir', '').to_s

        base = if imagesdir.empty?
                 docdir
               elsif File.absolute_path?(imagesdir)
                 imagesdir
               else
                 File.expand_path(imagesdir, docdir)
               end

        File.expand_path(target, base)
      end

      # Returns the absolute path where the converted PNG will be written.
      # Uses imagesoutdir when set; falls back to imagesdir, then docdir.
      # The PNG filename is derived from the .drawio basename only (no sub-directories
      # inside imagesoutdir), with the extension replaced by .png.
      def png_output_path(doc, target)
        docdir      = doc.attr('docdir', Dir.pwd).to_s
        imagesdir   = doc.attr('imagesdir', '').to_s
        imagesoutdir = doc.attr('imagesoutdir', '').to_s

        outdir = if !imagesoutdir.empty?
                   File.absolute_path?(imagesoutdir) ? imagesoutdir : File.expand_path(imagesoutdir, docdir)
                 elsif !imagesdir.empty?
                   File.absolute_path?(imagesdir) ? imagesdir : File.expand_path(imagesdir, docdir)
                 else
                   docdir
                 end

        basename = File.basename(target, '.*') + '.png'
        File.join(outdir, basename)
      end
    end
  end
end

Asciidoctor::Extensions.register do
  treeprocessor PresentationUtils::DrawioImage::DrawioImageProcessor
end
