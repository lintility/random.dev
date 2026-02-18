# rdv-base:runtime
# Alpine-based base for interpreted tools (Python, Node, shell scripts).
# Entrypoint wrapper validates the rdv contract before handing off to the tool.
#
# Build:
#   docker buildx build --platform linux/amd64,linux/arm64 -t rdv-base:runtime .

FROM alpine:3.19

LABEL org.opencontainers.image.title="rdv-base:runtime"
LABEL org.opencontainers.image.description="rdv base image for interpreted tools (Node, Python, shell)"
LABEL org.opencontainers.image.source="https://github.com/lintility/random.dev"
LABEL rdv.spec-version="0.1"

# Install common runtimes + contract runtime deps
# hadolint ignore=DL3018 -- base image version (alpine:3.19) pins the package set; individual pinning is redundant here
RUN apk add --no-cache \
    python3 \
    py3-pip \
    nodejs \
    npm \
    bash \
    curl \
    jq \
    ca-certificates \
    && rm -rf /var/cache/apk/*

# Copy the entrypoint wrapper (shell-based for runtime image)
COPY entrypoint.sh /rdv-entrypoint
RUN chmod +x /rdv-entrypoint

# Tool script must be COPY'd by tool Dockerfiles as /tool (or /tool.py, /tool.js, /tool.sh)
# tool-manifest.json must be COPY'd by tool Dockerfiles as /tool-manifest.json
ENTRYPOINT ["/rdv-entrypoint"]
