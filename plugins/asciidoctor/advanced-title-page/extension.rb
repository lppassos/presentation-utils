require "asciidoctor"
require "asciidoctor/extensions"
require "asciidoctor/pdf"


class PDFAdvancedTitlePage < (Asciidoctor::Converter.for 'pdf')
  register_for "pdf"

  include Asciidoctor::Logging
  include ::Asciidoctor::PDF

  def ink_title_page doc
    if doc.attr? 'advanced-title-page'
      title_text_align = (@theme.title_page_text_align || @base_text_align).to_sym
      render_title_page_logo doc, title_text_align
      render_text_parts doc, title_text_align
    else
      super
    end
  end

  def render_title_page_logo doc, title_text_align
    # Replicate the logic from the default title page for the logo
    if @theme.title_page_logo_display != 'none' && (logo_image_path = (doc.attr 'title-logo-image') || (logo_image_from_theme = @theme.title_page_logo_image))
      if (logo_image_path.include? ':') && logo_image_path =~ ImageAttributeValueRx
        logo_image_attrs = (::Asciidoctor::AttributeList.new $2).parse %w(alt width height)
        if logo_image_from_theme
          relative_to_imagesdir = false
          logo_image_path = apply_subs_discretely doc, $1, subs: [:attributes], imagesdir: @themesdir
          logo_image_path = ThemeLoader.resolve_theme_asset logo_image_path, @themesdir unless (::File.absolute_path? logo_image_path) || (doc.is_uri? logo_image_path)
        else
          relative_to_imagesdir = true
          logo_image_path = $1
        end
      else
        logo_image_attrs = {}
        relative_to_imagesdir = false
        if logo_image_from_theme
          logo_image_path = apply_subs_discretely doc, logo_image_path, subs: [:attributes], imagesdir: @themesdir
          logo_image_path = ThemeLoader.resolve_theme_asset logo_image_path, @themesdir unless (::File.absolute_path? logo_image_path) || (doc.is_uri? logo_image_path)
        end
      end
      if (::Asciidoctor::Image.target_and_format logo_image_path)[1] == 'pdf'
        log :error, %(PDF format not supported for title page logo image: #{logo_image_path})
      else
        logo_image_attrs['target'] = logo_image_path
        # NOTE: at the very least, title_text_align will be a valid alignment value
        logo_image_attrs['align'] = [(logo_image_attrs.delete 'align'), @theme.title_page_logo_align, title_text_align.to_s].find {|val| (BlockAlignmentNames.include? val) }
        if (logo_image_top = logo_image_attrs['top'] || @theme.title_page_logo_top)
          initial_y, @y = @y, (resolve_top logo_image_top)
        end
        # NOTE: pinned option keeps image on same page
        indent (@theme.title_page_logo_margin_left || 0), (@theme.title_page_logo_margin_right || 0) do
          # FIXME: add API to Asciidoctor for creating blocks outside of extensions
          convert_image (::Asciidoctor::Block.new doc, :image, content_model: :empty, attributes: logo_image_attrs), relative_to_imagesdir: relative_to_imagesdir, pinned: true
        end
        @y = initial_y if initial_y
      end
    end
  end

  def render_text_parts doc, title_text_align
    theme_font :title_page do
      if (title_top = @theme.title_page_title_top)
        @y = resolve_top title_top
      end
      unless @theme.title_page_title_display == 'none'
        doctitle = doc.doctitle partition: true
        move_down @theme.title_page_title_margin_top || 0
        indent (@theme.title_page_title_margin_left || 0), (@theme.title_page_title_margin_right || 0) do
          theme_font :title_page_title do
            ink_prose doctitle.main, align: title_text_align, margin: 0
          end
        end
        move_down @theme.title_page_title_margin_bottom || 0
      end
      if @theme.title_page_subtitle_display != 'none' && (subtitle = (doctitle || (doc.doctitle partition: true)).subtitle)
        move_down @theme.title_page_subtitle_margin_top || 0
        indent (@theme.title_page_subtitle_margin_left || 0), (@theme.title_page_subtitle_margin_right || 0) do
          theme_font :title_page_subtitle do
            ink_prose subtitle, align: title_text_align, margin: 0
          end
        end
        move_down @theme.title_page_subtitle_margin_bottom || 0
      end
      if @theme.title_page_authors_display != 'none'
        authors_text = apply_subs_discretely doc, @theme.advanced_title_page_authors_template

        move_down @theme.title_page_authors_margin_top || 0
        indent (@theme.title_page_authors_margin_left || 0), (@theme.title_page_authors_margin_right || 0) do
          theme_font :title_page_authors do
            authors_text.split("\n") do |line|
              ink_prose line, align: title_text_align, margin: 0, normalize: true
            end
          end
        end
        move_down @theme.title_page_authors_margin_bottom || 0
      end
      unless @theme.title_page_revision_display == 'none' || (revision_info = [(doc.attr? 'revnumber') ? %(#{doc.attr 'version-label'} #{doc.attr 'revnumber'}) : nil, (doc.attr 'revdate')].compact).empty?
        move_down @theme.title_page_revision_margin_top || 0
        revision_text = apply_subs_discretely doc, @theme.advanced_title_page_revision_template

        # revision_text = revision_info.join @theme.title_page_revision_delimiter
        # if (revremark = doc.attr 'revremark')
        #   revision_text = %(#{revision_text}: #{revremark})
        # end
        indent (@theme.title_page_revision_margin_left || 0), (@theme.title_page_revision_margin_right || 0) do
          theme_font :title_page_revision do
            ink_prose revision_text, align: title_text_align, margin: 0, normalize: false
          end
        end
        move_down @theme.title_page_revision_margin_bottom || 0
      end
    end
  end
end
