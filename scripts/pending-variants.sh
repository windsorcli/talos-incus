#!/bin/bash
set -euo pipefail

# Usage: ./scripts/pending-variants.sh <version> <arches> <variants>
#   Prints the comma-separated variants that the GitHub release for <version>
#   is missing at least one asset for. Prints every variant when the release
#   does not exist, and an empty line when the release is complete.

TALOS_VERSION="${1}"
ARCHES="${2}"
VARIANTS="${3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

if ! ASSETS="$(gh release view "${TALOS_VERSION}" --json assets --jq '.assets[].name' 2>/dev/null)"; then
  echo "${VARIANTS}"
  exit 0
fi

PENDING=()
IFS=',' read -ra ARCH_ARRAY <<< "${ARCHES}"
IFS=',' read -ra VARIANT_ARRAY <<< "${VARIANTS}"
for variant in "${VARIANT_ARRAY[@]}"; do
  missing=false
  for arch in "${ARCH_ARRAY[@]}"; do
    while read -r file; do
      for name in "${file}" "${file}.bundle"; do
        if ! grep -qxF "${name}" <<< "${ASSETS}"; then
          missing=true
        fi
      done
    done < <(variant_files "${variant}" "${arch}")
  done
  if [ "${missing}" = true ]; then
    PENDING+=("${variant}")
  fi
done

(IFS=,; echo "${PENDING[*]:-}")
