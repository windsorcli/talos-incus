#!/bin/bash
set -euo pipefail

# Usage: ./scripts/build-image.sh [version] [arch] [variant]
#   variant: default (Talos metal platform) or nocloud (Talos nocloud platform)

VERSION="${1:-v1.12.0}"
ARCH="${2:-amd64}"
VARIANT="${3:-default}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

UPSTREAM_URL="$(upstream_image_url "${VARIANT}" "${VERSION}" "${ARCH}")"
PREFIX="$(variant_prefix "${VARIANT}")"
ORIG_DIR="$(pwd)"
WORK_DIR="${ORIG_DIR}/build-${VARIANT}-${ARCH}"
RAW_FILE="${WORK_DIR}/$(basename "${UPSTREAM_URL}")"
METADATA_TARBALL="${PREFIX}-${ARCH}-incus.tar.xz"
DISK_FILE="${PREFIX}-${ARCH}.qcow2"

if [ "${VARIANT}" = "default" ]; then
  IMAGE_NAME="talos-${VERSION}-${ARCH}"
  DESCRIPTION="Talos Linux ${VERSION} (${ARCH})"
else
  IMAGE_NAME="talos-${VERSION}-${ARCH}-${VARIANT}"
  DESCRIPTION="Talos Linux ${VERSION} (${ARCH}, ${VARIANT})"
fi

echo "Creating split-format Talos ${VARIANT} image for ${ARCH} (${VERSION})..."

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

echo "Step 1: Downloading ${UPSTREAM_URL}..."
if [ -f "${RAW_FILE}" ]; then
  echo "  File already exists (presumably verified via cosign), skipping download"
else
  curl -L -f "${UPSTREAM_URL}" -o "${RAW_FILE}"
fi
echo "  sha256: $(sha256sum "${RAW_FILE}" | cut -d' ' -f1)"

echo "Step 2: Decompressing..."
RAW_DECOMPRESSED="${RAW_FILE%.zst}"
zstd -d "${RAW_FILE}" -o "${RAW_DECOMPRESSED}"

echo "Step 3: Converting to qcow2..."
QCOW2_FILE="${WORK_DIR}/${DISK_FILE}"
qemu-img convert -f raw -O qcow2 "${RAW_DECOMPRESSED}" "${QCOW2_FILE}"

echo "Step 4: Creating metadata.yaml..."
METADATA_YAML="${WORK_DIR}/metadata.yaml"
cat > "${METADATA_YAML}" <<EOF
architecture: "${ARCH}"
creation_date: $(date +%s)
properties:
  architecture: "${ARCH}"
  description: "${DESCRIPTION}"
  name: "${IMAGE_NAME}"
  os: "talos"
  release: "${VERSION}"
  variant: "${VARIANT}"
templates: {}
EOF

echo "Step 5: Creating metadata tarball..."
tar -cJf "${ORIG_DIR}/${METADATA_TARBALL}" "metadata.yaml"

echo "Step 6: Preparing disk image..."
cp "${QCOW2_FILE}" "${ORIG_DIR}/${DISK_FILE}"

cd "${ORIG_DIR}"
rm -rf "${WORK_DIR}"

echo ""
echo "✓ Successfully created split-format images:"
echo "  Metadata: ${METADATA_TARBALL} ($(du -h "${METADATA_TARBALL}" | cut -f1))"
echo "  Disk: ${DISK_FILE} ($(du -h "${DISK_FILE}" | cut -f1))"
