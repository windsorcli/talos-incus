#!/bin/bash
set -euo pipefail

# Usage: ./scripts/create-release.sh <version> <arches> <variants>
#   Creates the GitHub release with the assets of the given variants. If the
#   release already exists, uploads those assets to it (replacing any with the
#   same name) and refreshes the release notes.

TALOS_VERSION="${1}"
ARCHES="${2}"
VARIANTS="${3:-default}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

RELEASE_FILES=()
ARCH_LIST=""

IFS=',' read -ra ARCH_ARRAY <<< "${ARCHES}"
IFS=',' read -ra VARIANT_ARRAY <<< "${VARIANTS}"
for arch in "${ARCH_ARRAY[@]}"; do
  ARCH_LIST="${ARCH_LIST}- ${arch}"$'\n'
done
for variant in "${VARIANT_ARRAY[@]}"; do
  for arch in "${ARCH_ARRAY[@]}"; do
    while read -r file; do
      RELEASE_FILES+=("${file}" "${file}.bundle")
    done < <(variant_files "${variant}" "${arch}")
  done
done

NOTES="Automated release of Talos OS split-format images for Incus.

**Version:** ${TALOS_VERSION}

**Architectures:**
${ARCH_LIST}
**Variants:**
- \`default\`: Talos \`metal\` platform. Assets \`talos-<arch>-incus.tar.xz\` and \`talos-<arch>.qcow2\`.
- \`nocloud\`: Talos \`nocloud\` platform, which reads a \`cidata\` disk. Assets \`talos-nocloud-<arch>-incus.tar.xz\` and \`talos-nocloud-<arch>.qcow2\`.

**Usage (Simplestreams - Recommended):**

\`\`\`bash
incus remote add windsor https://images.windsorcli.dev --protocol simplestreams
incus image list windsor:
incus launch windsor:talos/${TALOS_VERSION}/amd64 my-instance
incus launch windsor:talos/${TALOS_VERSION}/amd64/nocloud my-nocloud-instance
\`\`\`

**Verification:**

Verify metadata and disk files:
\`\`\`bash
cosign verify-blob \
  --bundle talos-amd64-incus.tar.xz.bundle \
  --certificate-identity-regexp '^https://github.com/windsorcli/talos-incus' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  talos-amd64-incus.tar.xz

cosign verify-blob \
  --bundle talos-amd64.qcow2.bundle \
  --certificate-identity-regexp '^https://github.com/windsorcli/talos-incus' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  talos-amd64.qcow2
\`\`\`"

if gh release view "${TALOS_VERSION}" >/dev/null 2>&1; then
  gh release upload "${TALOS_VERSION}" --clobber "${RELEASE_FILES[@]}"
  gh release edit "${TALOS_VERSION}" --notes "${NOTES}"
else
  gh release create "${TALOS_VERSION}" \
    --title "Talos ${TALOS_VERSION}" \
    --notes "${NOTES}" \
    --latest \
    "${RELEASE_FILES[@]}"
fi
