# Start from the official Go base image. Keep this in step with the `go`
# directive in go.mod — an older builder cannot compile a newer module.
FROM golang:1.26-alpine AS builder

# Set working directory
WORKDIR /app

# Copy the manifests first so the dependency layer is cached independently of
# source changes; editing a .go file no longer re-downloads every module.
COPY go.mod go.sum ./
RUN go mod download

# Copy go source code
COPY . .
RUN go build -o server .

# Use a minimal image for running
FROM alpine:latest

# Set working directory
WORKDIR /app

# Copy the binary from the builder image
COPY --from=builder /app/server .

# Expose the port the server listens on
EXPOSE 8000

# Run the binary
CMD ["./server"]
