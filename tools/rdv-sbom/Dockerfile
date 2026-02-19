# rdv-sbom: SBOM generator using syft
FROM alpine:3.21

LABEL org.opencontainers.image.title="rdv-sbom"
LABEL org.opencontainers.image.description="SBOM generator (CycloneDX/SPDX) using syft"
LABEL org.opencontainers.image.source="https://github.com/lintility/random.dev"
LABEL rdv.spec-version="0.1"

# Install syft (Anchore SBOM generator) + deps
SHELL ["/bin/ash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3018
RUN apk add --no-cache bash curl jq ca-certificates \
    && curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
       | sh -s -- -b /usr/local/bin \
    && rm -rf /var/cache/apk/*

COPY entrypoint.sh /rdv-entrypoint
RUN chmod +x /rdv-entrypoint
COPY tool-manifest.json /tool-manifest.json

ENTRYPOINT ["/rdv-entrypoint"]
