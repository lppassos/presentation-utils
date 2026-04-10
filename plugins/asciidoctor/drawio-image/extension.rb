require 'asciidoctor'
require 'asciidoctor/extensions'
require 'fileutils'
require 'open3'

module PresentationUtils
  module DrawioImage
    class DrawioImageProcessor < Asciidoctor::Extensions::TreeProcessor
      include Asciidoctor::Logging

      def process(document)
        # Collect block images (context :image) and inline images (context :inline_image).
        nodes = document.find_by(context: :image)
        nodes += document.find_by(context: :inline_image)

        nodes.each do |node|
          target = node.attr('target').to_s
          next unless target.end_with?('.drawio')

          drawio_path = resolve_drawio_path(document, target)
          png_path    = png_output_path(document, target)

          if conversion_needed?(drawio_path, png_path)
            begin
              convert_to_png(drawio_path, png_path)
            rescue StandardError => e
              logger.error "drawio-image: skipping #{target} — #{e.message}"
              next
            end
          end

          node.set_attr('target', png_path)
        end

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

      # Returns true when the PNG does not yet exist or when the .drawio source is
      # newer than the existing PNG, meaning a fresh export is required.
      def conversion_needed?(drawio_path, png_path)
        return true unless File.exist?(png_path)

        File.mtime(drawio_path) > File.mtime(png_path)
      end

      # Shells out to drawio (via xvfb-run for headless operation) to export the
      # .drawio diagram as a PNG.  Raises RuntimeError on non-zero exit.
      def convert_to_png(drawio_path, png_path)
        FileUtils.mkdir_p(File.dirname(png_path))

        cmd = ['xvfb-run', '-a', 'drawio', '--no-sandbox', '-x', '-f', 'png', '-o', png_path, drawio_path]
        output, status = Open3.capture2e(*cmd)

        return if status.success?

        raise "drawio export failed for #{drawio_path} (exit #{status.exitstatus}): #{output.strip}"
      end
    end
  end
end

Asciidoctor::Extensions.register do
  treeprocessor PresentationUtils::DrawioImage::DrawioImageProcessor
end
