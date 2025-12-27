#!/bin/bash
set -euo pipefail

ARCHES="${1}"
GPG_PASSPHRASE="${2}"

GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format LONG | grep '^sec' | awk '{print $2}' | cut -d'/' -f2 | head -1)
echo "Signing with key: ${GPG_KEY_ID}"

IFS=',' read -ra ARCH_ARRAY <<< "${ARCHES}"
for arch in "${ARCH_ARRAY[@]}"; do
  for file in "talos-${arch}-incus.tar.xz" "talos-${arch}.qcow2"; do
    if [ -f "$file" ]; then
      gpg --batch --yes --detach-sign --armor \
        --pinentry-mode loopback \
        --passphrase "${GPG_PASSPHRASE}" \
        -u "${GPG_KEY_ID}" \
        -o "${file}.asc" \
        "${file}"
    fi
  done
done

echo "✓ Signatures created:"
ls -lh -- ./*.asc
