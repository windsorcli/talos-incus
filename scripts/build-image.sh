#!/bin/bash
set -euo pipefail

VERSION="${1:-v1.12.0}"
ARCH="${2:-amd64}"

BASE_URL="https://github.com/siderolabs/talos/releases/download/${VERSION}"
WORK_DIR="$(pwd)/build-${ARCH}"
RAW_FILE="${WORK_DIR}/metal-${ARCH}.raw.zst"
OUTPUT_FILE="incus-${ARCH}.tar.xz"

echo "Creating unified Talos image for ${ARCH} (${VERSION})..."

# Create work directory
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Step 1: Download
echo "Step 1: Downloading ${RAW_FILE}..."
curl -L -f "${BASE_URL}/metal-${ARCH}.raw.zst" -o "${RAW_FILE}"

# Step 2: Decompress
echo "Step 2: Decompressing..."
RAW_DECOMPRESSED="${WORK_DIR}/metal-${ARCH}.raw"
zstd -d "${RAW_FILE}" -o "${RAW_DECOMPRESSED}"

# Step 3: Convert to qcow2
echo "Step 3: Converting to qcow2..."
QCOW2_FILE="${WORK_DIR}/talos-${ARCH}.qcow2"
qemu-img convert -f raw -O qcow2 "${RAW_DECOMPRESSED}" "${QCOW2_FILE}"

# Step 4: Create metadata.yaml
echo "Step 4: Creating metadata.yaml..."
METADATA_FILE="${WORK_DIR}/metadata.yaml"
cat > "${METADATA_FILE}" <<EOF
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

# Step 5: Rename to rootfs.img
echo "Step 5: Preparing rootfs.img..."
ROOTFS_FILE="${WORK_DIR}/rootfs.img"
cp "${QCOW2_FILE}" "${ROOTFS_FILE}"

# Step 6: Create unified tarball (using xz compression for Incus simplestreams compatibility)
echo "Step 6: Creating unified tarball..."
cd "${WORK_DIR}"
tar -cJf "../${OUTPUT_FILE}" "metadata.yaml" "rootfs.img"

# Cleanup
cd ..
rm -rf "${WORK_DIR}"

echo ""
echo "✓ Successfully created ${OUTPUT_FILE}"
echo "  File size: $(du -h ${OUTPUT_FILE} | cut -f1)"
