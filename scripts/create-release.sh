#!/bin/bash
set -euo pipefail

TALOS_VERSION="${1}"
ARCHES="${2}"

RELEASE_FILES=()
ARCH_LIST=""

IFS=',' read -ra ARCH_ARRAY <<< "${ARCHES}"
for arch in "${ARCH_ARRAY[@]}"; do
  RELEASE_FILES+=("talos-${arch}-incus.tar.xz")
  RELEASE_FILES+=("talos-${arch}.qcow2")
  RELEASE_FILES+=("talos-${arch}-incus.tar.xz.asc")
  RELEASE_FILES+=("talos-${arch}.qcow2.asc")
  ARCH_LIST="${ARCH_LIST}- ${arch}\n"
done

NOTES="Automated release of Talos OS split-format images for Incus.

**Version:** ${TALOS_VERSION}

**Architectures:**
${ARCH_LIST}

**Usage (Simplestreams - Recommended):**

\`\`\`bash
incus remote add windsor https://images.windsorcli.dev --protocol simplestreams
incus image list windsor:
incus launch windsor:talos/${TALOS_VERSION}/amd64 my-instance
\`\`\`

**Verification:**

Verify metadata and disk files:
\`\`\`bash
gpg --verify talos-amd64-incus.tar.xz.asc talos-amd64-incus.tar.xz
gpg --verify talos-amd64.qcow2.asc talos-amd64.qcow2
\`\`\`"

gh release create "${TALOS_VERSION}" \
  --title "Talos ${TALOS_VERSION}" \
  --notes "${NOTES}" \
  --latest \
  "${RELEASE_FILES[@]}"

