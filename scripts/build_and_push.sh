#!/bin/bash

# Build and push multi-architecture Docker images for the 2048 game

set -e

# Configuration
REGISTRY="emnalmdr"
BACKEND_IMAGE="$REGISTRY/2048-backend"
FRONTEND_IMAGE="$REGISTRY/2048-frontend"
TAG="latest"
PLATFORMS="linux/amd64,linux/arm64"

echo "🔨 Building multi-architecture Docker images for platforms: $PLATFORMS"

# Check if buildx is available and create builder if needed
if ! docker buildx ls | grep -q multiarch; then
    echo "Creating multiarch builder..."
    docker buildx create --name multiarch --use --bootstrap
else
    echo "Using existing multiarch builder..."
    docker buildx use multiarch
fi

# Build and push backend image
echo "Building and pushing backend image for multiple architectures..."
cd backend
docker buildx build \
    --platform $PLATFORMS \
    --tag $BACKEND_IMAGE:$TAG \
    --no-cache \
    --push \
    .
cd ..

# Build and push frontend image  
echo "Building and pushing frontend image for multiple architectures..."
cd frontend
docker buildx build \
    --platform $PLATFORMS \
    --tag $FRONTEND_IMAGE:$TAG \
    --no-cache \
    --push \
    .
cd ..

echo "✅ Multi-architecture images built and pushed successfully!"
echo "Backend: $BACKEND_IMAGE:$TAG (platforms: $PLATFORMS)"
echo "Frontend: $FRONTEND_IMAGE:$TAG (platforms: $PLATFORMS)"

# Inspect the images to verify multi-arch
echo ""
echo "🔍 Verifying multi-architecture images..."
docker buildx imagetools inspect $BACKEND_IMAGE:$TAG
echo ""
docker buildx imagetools inspect $FRONTEND_IMAGE:$TAG