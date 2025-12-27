#!/bin/bash
set -euo pipefail

VERSION="${1:-v1.12.0}"
ARCH="${2:-amd64}"

BASE_URL="https://github.com/siderolabs/talos/releases/download/${VERSION}"
ORIG_DIR="$(pwd)"
WORK_DIR="${ORIG_DIR}/build-${ARCH}"
RAW_FILE="${WORK_DIR}/metal-${ARCH}.raw.zst"
METADATA_TARBALL="talos-${ARCH}-incus.tar.xz"
DISK_FILE="talos-${ARCH}.qcow2"

echo "Creating split-format Talos image for ${ARCH} (${VERSION})..."

# Create work directory
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Step 1: Download image (if not already present)
echo "Step 1: Downloading ${RAW_FILE}..."
if [ -f "${RAW_FILE}" ]; then
  echo "  File already exists (presumably verified via cosign), skipping download"
else
  curl -L -f "${BASE_URL}/metal-${ARCH}.raw.zst" -o "${RAW_FILE}"
  echo "  Note: Image should be verified via cosign before processing"
fi

# Step 2: Decompress
echo "Step 4: Decompressing..."
RAW_DECOMPRESSED="${WORK_DIR}/metal-${ARCH}.raw"
zstd -d "${RAW_FILE}" -o "${RAW_DECOMPRESSED}"

# Step 3: Convert to qcow2
echo "Step 3: Converting to qcow2..."
QCOW2_FILE="${WORK_DIR}/talos-${ARCH}.qcow2"
qemu-img convert -f raw -O qcow2 "${RAW_DECOMPRESSED}" "${QCOW2_FILE}"

# Step 4: Create metadata.yaml
echo "Step 4: Creating metadata.yaml..."
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

# Step 5: Create metadata tarball
echo "Step 5: Creating metadata tarball..."
tar -cJf "${ORIG_DIR}/${METADATA_TARBALL}" "metadata.yaml"

# Step 6: Copy disk image
echo "Step 6: Preparing disk image..."
cp "${QCOW2_FILE}" "${ORIG_DIR}/${DISK_FILE}"

# Cleanup
cd "${ORIG_DIR}"
rm -rf "${WORK_DIR}"

echo ""
echo "✓ Successfully created split-format images:"
echo "  Metadata: ${METADATA_TARBALL} ($(du -h "${METADATA_TARBALL}" | cut -f1))"
echo "  Disk: ${DISK_FILE} ($(du -h "${DISK_FILE}" | cut -f1))"
