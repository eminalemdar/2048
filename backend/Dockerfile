# Start from the official Go base image
FROM golang:1.22-alpine AS builder

# Set working directory
WORKDIR /app

# Copy go source code
COPY . .

# Download dependencies and build the Go app
RUN go mod download
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
