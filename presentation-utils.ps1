
docker run --rm `
    -v "${PWD}:/work" `
    -v "${HOME}/Documents/asccidoctor_styles:/themes/asciidoctor:ro" `
    -v "${HOME}/Documents/marp_styles:/themes/marp:ro" `
    presentation-utils $args
