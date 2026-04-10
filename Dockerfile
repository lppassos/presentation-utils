FROM debian:bookworm-slim

ARG DRAWIO_VERSION=24.7.17

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    RUBYOPT=-Eutf-8:utf-8 \
    PDF_THEMES_DIR=/themes/asciidoctor \
    MARP_THEMES_DIR=/themes/marp \
    MARP_BROWSER_PATH=/usr/bin/chromium \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    TMPDIR=/tmp \
    PUPPETEER_ARGS="--no-sandbox --disable-setui-sandbox --disable-dev-shm-usage" \
    PUPPETEER_SKILL_DOWNLOAD=1

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN set -euo pipefail; \
  arch="amd64"; \
  url="https://github.com/jgraph/drawio-desktop/releases/download/v${DRAWIO_VERSION}/drawio-${arch}-${DRAWIO_VERSION}.deb"; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
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
    xauth \
  && curl -fsSL -o /tmp/drawio.deb "$url" \
  && apt-get install -y --no-install-recommends /tmp/drawio.deb \
  && rm -rf /var/lib/apt/lists/* \
  && rm -f /tmp/drawio.deb \
  && ln -s /usr/bin/chromium /usr/bin/google-chrome

RUN gem install --no-document \
    asciidoctor \
    asciidoctor-pdf \
    asciidoctor-diagram \
    kramdown-asciidoc

RUN npm install -g --no-fund --no-audit @marp-team/marp-cli @marp-team/marp-core \
    highlight.js markdown-it-highlightjs mermaid @mermaid-js/mermaid-cli

#RUN npm install puppeteer
#    && npx puppeteer browsers install chrome-browser-shell

RUN mkdir -p /themes/asciidoctor/fonts /themes/marp /.npm /.cache /tmp \
    && chmod -R a+rwx /.cache \
    && chmod -R a+rwx /.npm \
    && chmod 1777 /tmp

COPY themes/marp/ /themes/marp/

# Default Asciidoctor PDF themes live under /themes/asciidoctor
# (users can mount their own directory there at runtime)

# draw.io desktop (for convertto-png)


COPY bin/convertto-asciidoc /usr/local/bin/convertto-asciidoc
COPY bin/convertto-pdf /usr/local/bin/convertto-pdf
COPY bin/convertto-png /usr/local/bin/convertto-png
COPY bin/convertto-presentation /usr/local/bin/convertto-presentation
COPY bin/presentations-utils /usr/local/bin/presentations-utils
COPY bin/marp-theme-embed.js /usr/local/lib/marp-theme-embed.js
COPY bin/engine.mjs /usr/local/lib/engine.mjs
COPY bin/marp-preprocess.mjs /usr/local/lib/marp-preprocess.mjs
COPY bin/path-utils.sh /usr/local/lib/path-utils.sh
COPY bin/puppeteer-config.json /usr/local/lib/puppeteer-config.json
COPY plugins/asciidoctor/ /plugins/asciidoctor/
COPY plugins/marp/ /plugins/marp/

RUN chmod +x \
    /usr/local/bin/convertto-asciidoc \
    /usr/local/bin/convertto-pdf \
    /usr/local/bin/convertto-png \
    /usr/local/bin/convertto-presentation \
    /usr/local/bin/presentations-utils \
    /usr/local/lib/path-utils.sh

#USER 1001:1001

WORKDIR /work

ENTRYPOINT ["/usr/local/bin/presentations-utils"]
CMD []
