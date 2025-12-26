#!/bin/bash
set -euo pipefail

VERSION="${1:-v1.12.0}"
ARCH="${2:-amd64}"

BASE_URL="https://github.com/siderolabs/talos/releases/download/${VERSION}"
WORK_DIR="$(pwd)/build-${ARCH}"
RAW_FILE="${WORK_DIR}/metal-${ARCH}.raw.zst"
METADATA_FILE="incus-${ARCH}.tar.xz"
DISK_FILE="disk-${ARCH}.qcow2"

echo "Creating split-format Talos image for ${ARCH} (${VERSION})..."

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

# Step 5: Create metadata tarball (metadata.yaml only, ~1KB)
echo "Step 5: Creating metadata tarball..."
cd "${WORK_DIR}"
tar -cJf "../${METADATA_FILE}" "metadata.yaml"

# Step 6: Copy disk image (qcow2 format for VM images)
echo "Step 6: Preparing disk image..."
cp "${QCOW2_FILE}" "../${DISK_FILE}"

# Cleanup
cd ..
rm -rf "${WORK_DIR}"

echo ""
echo "✓ Successfully created split-format images:"
echo "  Metadata: ${METADATA_FILE} ($(du -h ${METADATA_FILE} | cut -f1))"
echo "  Disk: ${DISK_FILE} ($(du -h ${DISK_FILE} | cut -f1))"
