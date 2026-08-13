# Start from the official Go base image. Keep this in step with the `go`
# directive in go.mod — an older builder cannot compile a newer module.
#
# Pinned to BUILDPLATFORM so multi-arch builds compile natively and cross-link
# via GOARCH, instead of running the whole toolchain under QEMU emulation.
FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS builder

# Set working directory
WORKDIR /app

# Copy the manifests first so the dependency layer is cached independently of
# source changes; editing a .go file no longer re-downloads every module.
COPY go.mod go.sum ./
RUN go mod download

# Copy go source code
COPY . .

# CGO_ENABLED=0 produces a fully static binary so the runtime stage needs no
# libc; -trimpath and -s -w drop build paths and debug symbols.
# TARGETOS/TARGETARCH are supplied by buildx for each requested platform.
ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} \
    go build -trimpath -ldflags="-s -w" -o server .

# Use a minimal image for running.
# alpine ships ca-certificates-bundle, which the AWS SDK needs for TLS.
FROM alpine:latest

# Run as an unprivileged, numeric UID. Kubernetes' runAsNonRoot check can only
# verify a numeric user, so the UID is pinned rather than left to a name.
RUN adduser --disabled-password --gecos "" --uid 10001 appuser

# Set working directory
WORKDIR /app

# Copy the binary from the builder image
COPY --from=builder /app/server .

USER 10001

# Expose the port the server listens on (>1024, so no privileges required)
EXPOSE 8000

# Run the binary
CMD ["./server"]
