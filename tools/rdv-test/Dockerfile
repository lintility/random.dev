# rdv-test: multi-language test runner
FROM alpine:3.21

LABEL org.opencontainers.image.title="rdv-test"
LABEL org.opencontainers.image.description="Multi-language test runner (Go, Rust, Node/Jest, Python/pytest)"
LABEL org.opencontainers.image.source="https://github.com/lintility/random.dev"
LABEL rdv.spec-version="0.1"

# hadolint ignore=DL3018
RUN apk add --no-cache \
    bash curl jq ca-certificates git \
    go nodejs npm python3 py3-pip cargo rust \
    && npm install -g jest vitest \
    && pip install --no-cache-dir pytest pytest-json-report \
    && rm -rf /var/cache/apk/*

COPY entrypoint.sh /rdv-entrypoint
RUN chmod +x /rdv-entrypoint
COPY tool-manifest.json /tool-manifest.json

ENTRYPOINT ["/rdv-entrypoint"]
