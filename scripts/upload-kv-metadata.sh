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

# Update products list (idempotent merge)
set +e
PRODUCTS_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${NAMESPACE_ID}/values/products:list" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" 2>&1)
set -e

EXISTING_PRODUCTS="[]"
if [ -n "${PRODUCTS_RESPONSE}" ] && echo "${PRODUCTS_RESPONSE}" | jq -e '.success == true' >/dev/null 2>&1; then
  # Cloudflare KV API returns the value in .result field as a JSON-encoded string
  # Example: {"success": true, "result": "[\"product:talos:v1.11.6:amd64:default\"]"}
  RESULT_VALUE=$(echo "${PRODUCTS_RESPONSE}" | jq -r '.result // empty' 2>/dev/null || echo "")
  if [ -n "${RESULT_VALUE}" ] && [ "${RESULT_VALUE}" != "null" ]; then
    # The result is always a JSON string, so parse it
    PARSED=$(echo "${RESULT_VALUE}" | jq -e '.' 2>/dev/null || echo "[]")
    if echo "${PARSED}" | jq -e 'type == "array"' >/dev/null 2>&1; then
      EXISTING_PRODUCTS="${PARSED}"
    fi
  fi
fi

# Ensure we have a valid JSON array
if ! echo "${EXISTING_PRODUCTS}" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "Warning: Existing products list is invalid, starting with empty array"
  EXISTING_PRODUCTS="[]"
fi

echo "Existing products: $(echo "${EXISTING_PRODUCTS}" | jq -c '.')"

# Merge new product keys idempotently (only add if not already present)
# Convert PRODUCT_KEYS array to JSON array for jq processing
NEW_KEYS_JSON=$(printf '%s\n' "${PRODUCT_KEYS[@]}" | jq -R . | jq -s .)

UPDATED_PRODUCTS=$(echo "${EXISTING_PRODUCTS}" | jq -r --argjson new_keys "${NEW_KEYS_JSON}" '
  . as $existing |
  $new_keys as $new |
  ($existing + $new) | unique
' 2>/dev/null)

# Validate the result
if ! echo "${UPDATED_PRODUCTS}" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "Error: Failed to merge products list"
  exit 1
fi

curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/${NAMESPACE_ID}/values/products:list" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "${UPDATED_PRODUCTS}"

echo "✓ Updated products list with $(echo "${UPDATED_PRODUCTS}" | jq 'length') products"

