# rdv-base:minimal
# Distroless base for compiled binaries (Go, Rust, C).
# Entrypoint wrapper validates the rdv contract before handing off to the tool.
#
# Build:
#   docker buildx build --platform linux/amd64,linux/arm64 -t rdv-base:minimal .

# Stage 1: build the entrypoint wrapper
FROM golang:1.22-alpine AS builder

WORKDIR /build
COPY entrypoint.go .

RUN go build -ldflags="-s -w" -o /entrypoint entrypoint.go

# Stage 2: distroless final image
FROM gcr.io/distroless/static-debian12:nonroot

LABEL org.opencontainers.image.title="rdv-base:minimal"
LABEL org.opencontainers.image.description="rdv base image for compiled binaries"
LABEL org.opencontainers.image.source="https://github.com/lintility/random.dev"
LABEL rdv.spec_version="0.1"

# Copy the entrypoint wrapper
COPY --from=builder /entrypoint /rdv-entrypoint

# Tool binary must be COPY'd by tool Dockerfiles as /tool
# tool-manifest.json must be COPY'd by tool Dockerfiles as /tool-manifest.json
ENTRYPOINT ["/rdv-entrypoint"]
