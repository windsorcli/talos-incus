#!/bin/bash
set -euo pipefail

# Usage: ./scripts/sign-artifacts.sh <arches> <variants>
#   arches and variants are comma-separated, for example amd64,arm64 and default,nocloud.

ARCHES="${1}"
VARIANTS="${2:-default}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "Signing artifacts with cosign (OIDC keyless)"

IFS=',' read -ra ARCH_ARRAY <<< "${ARCHES}"
IFS=',' read -ra VARIANT_ARRAY <<< "${VARIANTS}"
for variant in "${VARIANT_ARRAY[@]}"; do
  for arch in "${ARCH_ARRAY[@]}"; do
    while read -r file; do
      if [ ! -f "${file}" ]; then
        echo "Error: ${file} not found"
        exit 1
      fi
      echo "Signing ${file}..."
      cosign sign-blob \
        --yes \
        --bundle "${file}.bundle" \
        "${file}"
    done < <(variant_files "${variant}" "${arch}")
  done
done

echo "✓ Signatures created:"
ls -lh -- ./*.bundle
