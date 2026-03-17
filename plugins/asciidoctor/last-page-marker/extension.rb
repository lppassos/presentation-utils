require 'asciidoctor'
require 'asciidoctor/extensions'
require 'asciidoctor/pdf'

module PresentationUtils
  module LastPageMarker
    class LastPageImageConverter < (Asciidoctor::Converter.for 'pdf')
      include Asciidoctor::Logging
      include ::Asciidoctor::PDF

      register_for 'pdf'

      def convert_document doc
        @last_page_marker_doc = doc
        if marker_enabled? && marker_position == 'inline'
          append_inline_marker doc
        end
        super
      end

      def write pdf_doc, target
        if marker_enabled? && marker_position == 'bottom'
          stamp_marker_on_last_page
        end
        super
      end

      private

      def marker_enabled?
        !(marker_theme_image_value.to_s.strip.empty?)
      end

      def marker_theme_image_value
        @theme&.[](:last_page_marker_image)
      end

      def marker_position
        (@theme&.[](:last_page_marker_position) || 'bottom').to_s.downcase
      end

      def marker_alignment
        (@theme&.[](:last_page_marker_alignment) || 'center').to_s.downcase
      end

      def marker_alignment_sym
        case marker_alignment
        when 'left' then :left
        when 'right' then :right
        else :center
        end
      end

      def parse_theme_image_value
        raw = marker_theme_image_value.to_s.strip
        return nil if raw.empty?

        if raw.include?(':') && raw =~ ImageAttributeValueRx
          attrlist = $2
          image_attrs = (::Asciidoctor::AttributeList.new attrlist).parse %w(alt width height fit)
          image_target = $1
          [image_target, image_attrs]
        else
          [raw, {}]
        end
      end

      def resolve_marker_image_path doc, image_target
        return [image_target, nil] if image_target.nil?
        image_target = apply_subs_discretely doc, image_target, subs: [:attributes], imagesdir: @themesdir

        if !(::File.absolute_path? image_target) && !(doc.is_uri? image_target)
          image_target = ThemeLoader.resolve_theme_asset image_target, @themesdir
        end

        [image_target, ::Asciidoctor::Image.target_and_format(image_target)[1]]
      end

      def last_non_imported_page_number
        pgnum = page_count
        while pgnum > 0
          pg = state.pages[pgnum - 1]
          return pgnum unless pg.imported_page?
          pgnum -= 1
        end
        nil
      end

      def stamp_marker_on_last_page
        doc = @last_page_marker_doc
        return unless doc

        image_target, image_attrs = parse_theme_image_value
        return unless image_target

        image_path, image_format = resolve_marker_image_path doc, image_target
        unless image_path && ::File.readable?(image_path)
          log :warn, %(last page marker image not found or not readable: #{image_path})
          return
        end

        pgnum = last_non_imported_page_number
        return unless pgnum

        if page_margin_bottom.to_f <= 0
          log :warn, 'last page marker skipped: bottom page margin is 0'
          return
        end

        prev = page_number
        float do
          canvas do
            go_to_page pgnum

            box_left = page_margin_left
            box_width = page_width - page_margin_left - page_margin_right
            box_height = page_margin_bottom
            box_top = box_height

            bounding_box [box_left, box_top], width: box_width, height: box_height do
              img_opts = resolve_image_options(image_path, image_format, image_attrs, container_size: [box_width, box_height])
              img_opts[:position] = marker_alignment_sym
              img_opts[:vposition] = :bottom
              image image_path, img_opts
            end
          end
        ensure
          go_to_page prev if prev && page_number != prev
        end
      end

      def append_inline_marker doc
        image_target, image_attrs = parse_theme_image_value
        return unless image_target

        image_path, _image_format = resolve_marker_image_path doc, image_target
        unless image_path && ::File.readable?(image_path)
          log :warn, %(last page marker image not found or not readable: #{image_path})
          return
        end

        attrs = {
          'target' => image_path,
          'align' => marker_alignment,
        }

        if (w = image_attrs['width'])
          attrs['width'] = w
        end
        if (h = image_attrs['height'])
          attrs['height'] = h
        end
        if (fit = image_attrs['fit'])
          attrs['fit'] = fit
        end
        if (alt = image_attrs['alt'])
          attrs['alt'] = alt
        end

        img_block = ::Asciidoctor::Block.new doc, :image, content_model: :empty, attributes: attrs
        doc.blocks << img_block
        nil
      end
    end
  end
end
