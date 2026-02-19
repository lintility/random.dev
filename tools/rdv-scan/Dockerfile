# rdv-scan: vulnerability scanner using grype
FROM alpine:3.21

LABEL org.opencontainers.image.title="rdv-scan"
LABEL org.opencontainers.image.description="Vulnerability scanner using grype"
LABEL org.opencontainers.image.source="https://github.com/lintility/random.dev"
LABEL rdv.spec-version="0.1"

SHELL ["/bin/ash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3018
RUN apk add --no-cache bash curl jq ca-certificates \
    && curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh \
       | sh -s -- -b /usr/local/bin \
    && rm -rf /var/cache/apk/*

COPY entrypoint.sh /rdv-entrypoint
RUN chmod +x /rdv-entrypoint
COPY tool-manifest.json /tool-manifest.json

ENTRYPOINT ["/rdv-entrypoint"]
