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

# Step 1: Download checksums
echo "Step 1: Downloading checksums..."
curl -L -f "${BASE_URL}/sha256sum.txt" -o "${WORK_DIR}/sha256sum.txt"

# Step 2: Download image
echo "Step 2: Downloading ${RAW_FILE}..."
curl -L -f "${BASE_URL}/metal-${ARCH}.raw.zst" -o "${RAW_FILE}"

# Step 3: Verify checksum
echo "Step 3: Verifying checksum..."
EXPECTED_HASH=$(grep "metal-${ARCH}.raw.zst" "${WORK_DIR}/sha256sum.txt" | awk '{print $1}')
if [ -z "${EXPECTED_HASH}" ]; then
  echo "Error: Could not find checksum for metal-${ARCH}.raw.zst in sha256sum.txt"
  exit 1
fi
ACTUAL_HASH=$(sha256sum "${RAW_FILE}" | awk '{print $1}')
if [ "${EXPECTED_HASH}" != "${ACTUAL_HASH}" ]; then
  echo "Error: Checksum mismatch for metal-${ARCH}.raw.zst"
  echo "  Expected: ${EXPECTED_HASH}"
  echo "  Actual:   ${ACTUAL_HASH}"
  exit 1
fi
echo "✓ Checksum verified: ${EXPECTED_HASH}"

# Step 4: Decompress
echo "Step 4: Decompressing..."
RAW_DECOMPRESSED="${WORK_DIR}/metal-${ARCH}.raw"
zstd -d "${RAW_FILE}" -o "${RAW_DECOMPRESSED}"

# Step 5: Convert to qcow2
echo "Step 5: Converting to qcow2..."
QCOW2_FILE="${WORK_DIR}/talos-${ARCH}.qcow2"
qemu-img convert -f raw -O qcow2 "${RAW_DECOMPRESSED}" "${QCOW2_FILE}"

# Step 6: Create metadata.yaml
echo "Step 6: Creating metadata.yaml..."
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

# Step 7: Create metadata tarball
echo "Step 7: Creating metadata tarball..."
tar -cJf "${ORIG_DIR}/${METADATA_TARBALL}" "metadata.yaml"

# Step 8: Copy disk image
echo "Step 8: Preparing disk image..."
cp "${QCOW2_FILE}" "${ORIG_DIR}/${DISK_FILE}"

# Cleanup
cd "${ORIG_DIR}"
rm -rf "${WORK_DIR}"

echo ""
echo "✓ Successfully created split-format images:"
echo "  Metadata: ${METADATA_TARBALL} ($(du -h "${METADATA_TARBALL}" | cut -f1))"
echo "  Disk: ${DISK_FILE} ($(du -h "${DISK_FILE}" | cut -f1))"
