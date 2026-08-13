#!/bin/bash

# Build and push multi-architecture Docker images for the 2048 game.
#
# Usage:
#   ./scripts/build_and_push.sh [tag]
#
# The tag defaults to the current git short SHA, which keeps every push
# rollback-able. A moving :latest tag is pushed alongside it for convenience,
# but deployment manifests should reference the immutable tag.
#
# Environment overrides:
#   REGISTRY   Docker Hub namespace (default: emnalmdr)
#   PLATFORMS  buildx platform list (default: linux/amd64,linux/arm64)
#   NO_CACHE   set to "true" to force a clean rebuild

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

REGISTRY="${REGISTRY:-emnalmdr}"
BACKEND_IMAGE="$REGISTRY/2048-backend"
FRONTEND_IMAGE="$REGISTRY/2048-frontend"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER_NAME="multiarch"

# Default to the git short SHA so the tag identifies exactly what was built.
if [ $# -ge 1 ]; then
    TAG="$1"
elif git -C "$PROJECT_ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
    TAG="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)"
else
    echo "ERROR: no tag given and not a git repository" >&2
    exit 1
fi

CACHE_FLAG=()
if [ "${NO_CACHE:-false}" = "true" ]; then
    CACHE_FLAG=(--no-cache)
fi

echo "🔨 Building multi-architecture images"
echo "   registry:  $REGISTRY"
echo "   tag:       $TAG (also pushing :latest)"
echo "   platforms: $PLATFORMS"
echo ""

# Warn about a dirty tree: the tag would claim to be a commit it is not.
if ! git -C "$PROJECT_ROOT" diff --quiet HEAD 2>/dev/null; then
    echo "⚠️  Working tree has uncommitted changes — the image will not match tag $TAG exactly."
    echo ""
fi

# Fail before a long build rather than after it.
if ! grep -q "index.docker.io" "${DOCKER_CONFIG:-$HOME/.docker}/config.json" 2>/dev/null; then
    echo "ERROR: no Docker Hub credentials found. Run: docker login" >&2
    exit 1
fi

# Reuse the buildx builder if it already exists. The name is anchored so a
# builder merely containing this substring is not mistaken for it.
if docker buildx ls --format '{{.Name}}' 2>/dev/null | grep -qx "$BUILDER_NAME"; then
    echo "Using existing $BUILDER_NAME builder..."
    docker buildx use "$BUILDER_NAME"
else
    echo "Creating $BUILDER_NAME builder..."
    docker buildx create --name "$BUILDER_NAME" --use --bootstrap
fi

build_and_push() {
    local name="$1" context="$2" image="$3"

    echo ""
    echo "▶ Building and pushing $name..."
    # The ${arr[@]+"${arr[@]}"} form is needed because macOS ships bash 3.2,
    # where expanding an empty array under `set -u` is an unbound-variable error.
    docker buildx build \
        --platform "$PLATFORMS" \
        --tag "$image:$TAG" \
        --tag "$image:latest" \
        ${CACHE_FLAG[@]+"${CACHE_FLAG[@]}"} \
        --push \
        "$context"
}

# NOTE: the frontend is built without VITE_API_URL on purpose. In the cluster
# the ALB serves the app and the API from one origin, so the bundle must use
# relative paths. docker-compose passes the build arg for local development.
build_and_push "backend"  "$PROJECT_ROOT/backend"  "$BACKEND_IMAGE"
build_and_push "frontend" "$PROJECT_ROOT/frontend" "$FRONTEND_IMAGE"

echo ""
echo "✅ Images pushed"
echo "   $BACKEND_IMAGE:$TAG"
echo "   $FRONTEND_IMAGE:$TAG"

echo ""
echo "🔍 Verifying multi-architecture manifests..."
for image in "$BACKEND_IMAGE" "$FRONTEND_IMAGE"; do
    echo ""
    echo "--- $image:$TAG ---"
    docker buildx imagetools inspect "$image:$TAG" \
        --format '{{range .Manifest.Manifests}}{{.Platform.OS}}/{{.Platform.Architecture}} {{end}}'
done

echo ""
echo "Next: update the image tags in kubernetes/kro/instances/game2048-app-instance.yaml to :$TAG"
