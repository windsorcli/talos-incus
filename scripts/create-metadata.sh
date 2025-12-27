#!/bin/bash
set -euo pipefail

VERSION="${1:-v1.12.0}"
ARCH="${2:-amd64}"

ORIG_DIR="$(pwd)"
WORK_DIR="${ORIG_DIR}/build-${ARCH}"
METADATA_TARBALL="talos-${ARCH}-incus.tar.xz"

echo "Creating metadata tarball for Talos ${ARCH} (${VERSION})..."
echo "Note: qcow2 images are now proxied from Talos image factory"

# Create work directory
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Create metadata.yaml
echo "Creating metadata.yaml..."
METADATA_YAML="${WORK_DIR}/metadata.yaml"
cat > "${METADATA_YAML}" <<EOF
architecture: "${ARCH}"
creation_date: $(date +%s)
properties:
  architecture: "${ARCH}"
  description: "Talos Linux ${VERSION} (${ARCH})"
  name: "talos-${VERSION}-${ARCH}"
  os: "talos"
  release: "${VERSION}"
  variant: "default"
templates: {}
EOF

# Create metadata tarball
echo "Creating metadata tarball..."
tar -cJf "${ORIG_DIR}/${METADATA_TARBALL}" "metadata.yaml"

# Cleanup
cd "${ORIG_DIR}"
rm -rf "${WORK_DIR}"

echo ""
echo "✓ Successfully created metadata tarball:"
echo "  Metadata: ${METADATA_TARBALL} ($(du -h "${METADATA_TARBALL}" | cut -f1))"
echo "  Note: qcow2 disk images are proxied from Talos image factory"
