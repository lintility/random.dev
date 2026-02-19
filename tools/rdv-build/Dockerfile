# rdv-build: multi-language build tool
# Supports: Go, Rust, TypeScript/Node, Python
# Auto-detects language from workspace; falls back to build.rdv.yaml config
FROM alpine:3.21

LABEL org.opencontainers.image.title="rdv-build"
LABEL org.opencontainers.image.description="Multi-language build tool for rdv pipelines"
LABEL org.opencontainers.image.source="https://github.com/lintility/random.dev"
LABEL rdv.spec-version="0.1"

# Install language toolchains + contract runtime deps
# hadolint ignore=DL3018
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    ca-certificates \
    git \
    go \
    nodejs \
    npm \
    python3 \
    py3-pip \
    py3-setuptools \
    py3-wheel \
    cargo \
    rust \
    && rm -rf /var/cache/apk/*

COPY entrypoint.sh /rdv-entrypoint
RUN chmod +x /rdv-entrypoint
COPY tool-manifest.json /tool-manifest.json

ENTRYPOINT ["/rdv-entrypoint"]
