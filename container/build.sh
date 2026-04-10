#!/bin/bash
# Build the NanoClaw agent container image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="nanoclaw-agent"
TAG="${1:-latest}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-container}"

echo "Building NanoClaw agent container image..."
echo "Image: ${IMAGE_NAME}:${TAG}"

# Apple Container's buildkit chokes on symlinks in node_modules when building
# the context archive (.dockerignore doesn't help — the error occurs before
# ignore rules are applied). Move node_modules out during build.
NM_DIR="$SCRIPT_DIR/agent-runner/node_modules"
NM_BACKUP=""
if [ -d "$NM_DIR" ]; then
  NM_BACKUP=$(mktemp -d)
  mv "$NM_DIR" "$NM_BACKUP/node_modules"
  trap 'mv "$NM_BACKUP/node_modules" "$NM_DIR" 2>/dev/null; rm -rf "$NM_BACKUP"' EXIT
fi

${CONTAINER_RUNTIME} build -t "${IMAGE_NAME}:${TAG}" .

echo ""
echo "Build complete!"
echo "Image: ${IMAGE_NAME}:${TAG}"
echo ""
echo "Test with:"
echo "  echo '{\"prompt\":\"What is 2+2?\",\"groupFolder\":\"test\",\"chatJid\":\"test@g.us\",\"isMain\":false}' | ${CONTAINER_RUNTIME} run -i ${IMAGE_NAME}:${TAG}"
