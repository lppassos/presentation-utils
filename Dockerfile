FROM debian:bookworm-slim

ARG DRAWIO_VERSION=24.7.17

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    RUBYOPT=-Eutf-8:utf-8 \
    PDF_THEMES_DIR=/themes \
    MARP_THEMES_DIR=/themes/marp \
    MARP_BROWSER_PATH=/usr/bin/chromium

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    chromium \
    curl \
    fontconfig \
    fonts-dejavu-core \
    fonts-liberation \
    graphviz \
    nodejs \
    npm \
    openjdk-17-jre-headless \
    qpdf \
    ruby-full \
    xvfb \
  && rm -rf /var/lib/apt/lists/*

RUN gem install --no-document \
    asciidoctor \
    asciidoctor-pdf \
    asciidoctor-diagram \
    kramdown-asciidoc

RUN npm install -g --no-fund --no-audit @marp-team/marp-cli

RUN mkdir -p /themes /themes/fonts /themes/marp

COPY themes/marp/ /themes/marp/

# draw.io desktop (for convertto-png)
RUN set -euo pipefail; \
  arch="amd64"; \
  url="https://github.com/jgraph/drawio-desktop/releases/download/v${DRAWIO_VERSION}/drawio-${arch}-${DRAWIO_VERSION}.deb"; \
  curl -fsSL -o /tmp/drawio.deb "$url"; \
  apt-get update; \
  apt-get install -y --no-install-recommends /tmp/drawio.deb; \
  rm -f /tmp/drawio.deb; \
  rm -rf /var/lib/apt/lists/*

COPY bin/convertto-asciidoc /usr/local/bin/convertto-asciidoc
COPY bin/convertto-pdf /usr/local/bin/convertto-pdf
COPY bin/convertto-png /usr/local/bin/convertto-png
COPY bin/convertto-marp /usr/local/bin/convertto-marp
COPY bin/marp-theme-embed.js /usr/local/lib/marp-theme-embed.js

RUN chmod +x \
    /usr/local/bin/convertto-asciidoc \
    /usr/local/bin/convertto-pdf \
    /usr/local/bin/convertto-png \
    /usr/local/bin/convertto-marp

WORKDIR /work

CMD ["bash"]
