#!/bin/bash
set -euo pipefail

TALOS_VERSION="${1}"
ARCHES="${2}"

RELEASE_FILES=()
ARCH_LIST=""

IFS=',' read -ra ARCH_ARRAY <<< "${ARCHES}"
for arch in "${ARCH_ARRAY[@]}"; do
  # Only include metadata files (qcow2 images are proxied from Talos factory)
  RELEASE_FILES+=("talos-${arch}-incus.tar.xz")
  RELEASE_FILES+=("talos-${arch}-incus.tar.xz.bundle")
  ARCH_LIST="${ARCH_LIST}- ${arch}"$'\n'
done

NOTES="Automated release of Talos OS metadata for Incus.

**Version:** ${TALOS_VERSION}

**Architectures:**
${ARCH_LIST}

**Note:** qcow2 disk images are now proxied from Talos image factory (https://factory.talos.dev).

**Usage (Simplestreams - Recommended):**

\`\`\`bash
incus remote add windsor https://images.windsorcli.dev --protocol simplestreams
incus image list windsor:
incus launch windsor:talos/${TALOS_VERSION}/amd64 my-instance
\`\`\`

**Verification:**

Verify metadata files:
\`\`\`bash
cosign verify-blob \
  --bundle talos-amd64-incus.tar.xz.bundle \
  --certificate-identity-regexp '^https://github.com/windsorcli/talos-incus' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  talos-amd64-incus.tar.xz
\`\`\`"

gh release create "${TALOS_VERSION}" \
  --title "Talos ${TALOS_VERSION}" \
  --notes "${NOTES}" \
  --latest \
  "${RELEASE_FILES[@]}"

