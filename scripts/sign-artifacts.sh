#!/bin/bash
set -euo pipefail

ARCHES="${1}"

echo "Signing artifacts with cosign (OIDC keyless)"

IFS=',' read -ra ARCH_ARRAY <<< "${ARCHES}"
for arch in "${ARCH_ARRAY[@]}"; do
  # Only sign metadata files (qcow2 images are proxied from Talos factory)
  file="talos-${arch}-incus.tar.xz"
  if [ -f "$file" ]; then
    echo "Signing ${file}..."
    cosign sign-blob \
      --yes \
      --bundle "${file}.bundle" \
      "${file}"
  fi
done

echo "✓ Signatures created:"
ls -lh -- ./*.bundle
