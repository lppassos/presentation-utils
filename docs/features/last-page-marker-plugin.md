In some asciidoctor documents I want to have the bottom of the last pageshowing an image that i specify in the theme.

We will have a plugin LastPageImageConverter, that will modify the last page to include an image. at the bottom.

The plugin will only activate if the theme includes the variable `last-page-marker-image` with the name of the image to include.

Additional fields that can be specified in the theme:

* `last-page-marker-position`
* `last-page-marker-alignment`

The position can be `bottom` or `inline`.

If it is bottom, it will be placed in the bottom of the page. It if is inline, it is placed right after the last line of text.

The alignment can be `left`, `center` or `right` specifying if the image is left aligned, centered or right aligned.
