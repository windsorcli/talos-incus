#!/bin/bash
set -euo pipefail

NAMESPACE_ID="${1}"
API_TOKEN="${2}"
ACCOUNT_ID="${3}"
TALOS_VERSION="${4}"
ARCHES="${5}"

CREATION_DATE=$(date +%s)
PRODUCT_KEYS=()

IFS=',' read -ra ARCH_ARRAY <<< "${ARCHES}"
for arch in "${ARCH_ARRAY[@]}"; do
  META_FILE="talos-${arch}-incus.tar.xz"
  DISK_FILE="talos-${arch}.qcow2"
  
  if [ ! -f "${META_FILE}" ] || [ ! -f "${DISK_FILE}" ]; then
    echo "Error: Missing files for ${arch}"
    exit 1
  fi
  
  META_HASH=$(sha256sum "${META_FILE}" | cut -d' ' -f1)
  DISK_HASH=$(sha256sum "${DISK_FILE}" | cut -d' ' -f1)
  META_SIZE=$(stat -c%s "${META_FILE}")
  DISK_SIZE=$(stat -c%s "${DISK_FILE}")
  
  cat "${META_FILE}" "${DISK_FILE}" | sha256sum | cut -d' ' -f1 > /tmp/combined_hash
  COMBINED_HASH=$(cat /tmp/combined_hash)
  
  PRODUCT_KEY="product:talos:${TALOS_VERSION}:${arch}:default"
  PRODUCT_KEYS+=("${PRODUCT_KEY}")
  
  METADATA=$(jq -n \
    --arg meta_hash "${META_HASH}" \
    --arg disk_hash "${DISK_HASH}" \
    --arg combined_hash "${COMBINED_HASH}" \
    --arg meta_size "${META_SIZE}" \
    --arg disk_size "${DISK_SIZE}" \
    --arg date "${CREATION_DATE}" \
    --arg github_repo "talos-incus" \
    '{
      meta_hash: $meta_hash,
      meta_size: ($meta_size | tonumber),
      disk_hash: $disk_hash,
      disk_size: ($disk_size | tonumber),
      combined_hash: $combined_hash,
      creation_date: ($date | tonumber),
      github_repo: $github_repo
    }')
  
  curl -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${NAMESPACE_ID}/values/${PRODUCT_KEY}" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "${METADATA}"
  
  echo "✓ Uploaded metadata for ${PRODUCT_KEY}"
done

# Update products list
set +e
PRODUCTS_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${NAMESPACE_ID}/values/products:list" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" 2>&1)
set -e

EXISTING_PRODUCTS="[]"
if [ -n "${PRODUCTS_RESPONSE}" ] && echo "${PRODUCTS_RESPONSE}" | jq -e '.success == true' >/dev/null 2>&1; then
  RESULT_VALUE=$(echo "${PRODUCTS_RESPONSE}" | jq -r '.result // "[]"' 2>/dev/null || echo "[]")
  if [ "${RESULT_VALUE}" != "null" ] && [ -n "${RESULT_VALUE}" ]; then
    EXISTING_PRODUCTS="${RESULT_VALUE}"
  fi
fi

# Build jq filter to add all product keys
JQ_FILTER='.'
for key in "${PRODUCT_KEYS[@]}"; do
  JQ_FILTER="${JQ_FILTER} | if index(\"${key}\") == null then . + [\"${key}\"] else . end"
done

UPDATED_PRODUCTS=$(echo "${EXISTING_PRODUCTS}" | jq -r "${JQ_FILTER}" 2>/dev/null || echo "${EXISTING_PRODUCTS}")

curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${NAMESPACE_ID}/values/products:list" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "${UPDATED_PRODUCTS}"

echo "✓ Updated products list"

