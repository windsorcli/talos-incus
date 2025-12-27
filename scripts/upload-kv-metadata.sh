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
  
  if [ ! -f "${META_FILE}" ]; then
    echo "Error: Missing metadata file for ${arch}"
    exit 1
  fi
  
  META_HASH=$(sha256sum "${META_FILE}" | cut -d' ' -f1)
  META_SIZE=$(stat -c%s "${META_FILE}")
  
  # Fetch qcow2 info from Talos image factory
  # URL pattern: https://factory.talos.dev/image/{schematic_id}/{version}/metal-{arch}.qcow2
  # Default schematic ID for vanilla Talos: 376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba
  TALOS_SCHEMATIC_ID="${TALOS_SCHEMATIC_ID:-376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba}"
  # Version can be with or without 'v' prefix
  FACTORY_VERSION="${TALOS_VERSION}"
  if [[ ! "${FACTORY_VERSION}" =~ ^v ]]; then
    FACTORY_VERSION="v${FACTORY_VERSION}"
  fi
  TALOS_FACTORY_URL="https://factory.talos.dev/image/${TALOS_SCHEMATIC_ID}/${FACTORY_VERSION}/metal-${arch}.qcow2"
  
  echo "Fetching qcow2 info from Talos factory: ${TALOS_FACTORY_URL}"
  
  # Get size from HEAD request (no download needed)
  echo "Getting file size from headers..."
  DISK_SIZE=$(curl -s -I -L -f "${TALOS_FACTORY_URL}" | grep -i "content-length" | awk '{print $2}' | tr -d '\r\n')
  if [ -z "${DISK_SIZE}" ]; then
    echo "Error: Failed to get file size from Talos factory"
    exit 1
  fi
  echo "  Size: ${DISK_SIZE} bytes"
  
  # Download and calculate hash in one pass (stream to sha256sum)
  echo "Downloading and calculating hash..."
  TEMP_QCOW2="/tmp/talos-${arch}-${TALOS_VERSION}.qcow2"
  if ! curl -L -f "${TALOS_FACTORY_URL}" -o "${TEMP_QCOW2}"; then
    echo "Error: Failed to download qcow2 from Talos factory"
    exit 1
  fi
  
  DISK_HASH=$(sha256sum "${TEMP_QCOW2}" | cut -d' ' -f1)
  echo "  Hash: ${DISK_HASH}"
  
  # Calculate combined hash (metadata + disk concatenated)
  cat "${META_FILE}" "${TEMP_QCOW2}" | sha256sum | cut -d' ' -f1 > /tmp/combined_hash
  COMBINED_HASH=$(cat /tmp/combined_hash)
  
  # Cleanup temp file
  rm -f "${TEMP_QCOW2}"
  
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
    --arg talos_factory_url "${TALOS_FACTORY_URL}" \
    --arg talos_schematic_id "${TALOS_SCHEMATIC_ID}" \
    '{
      meta_hash: $meta_hash,
      meta_size: ($meta_size | tonumber),
      disk_hash: $disk_hash,
      disk_size: ($disk_size | tonumber),
      combined_hash: $combined_hash,
      creation_date: ($date | tonumber),
      github_repo: $github_repo,
      talos_factory_url: $talos_factory_url,
      talos_schematic_id: $talos_schematic_id
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
if [ -n "${PRODUCTS_RESPONSE}" ]; then
  # Cloudflare KV API GET can return the value in two formats:
  # 1. Direct value in response body (if key exists): "[\"product:talos:v1.11.6:amd64:default\"]"
  # 2. Wrapped in API v4 format: {"success": true, "result": "[\"product:talos:v1.11.6:amd64:default\"]"}
  # 3. Error response: {"success": false, "errors": [...]}
  
  # Check if it's the wrapped API v4 format
  if echo "${PRODUCTS_RESPONSE}" | jq -e '.success == true' >/dev/null 2>&1; then
    # Extract from .result field and parse JSON string
    RESULT_VALUE=$(echo "${PRODUCTS_RESPONSE}" | jq -r '.result // empty' 2>/dev/null || echo "")
    if [ -n "${RESULT_VALUE}" ] && [ "${RESULT_VALUE}" != "null" ]; then
      # Parse the JSON string to get the actual array
      PARSED=$(echo "${RESULT_VALUE}" | jq -e '.' 2>/dev/null || echo "[]")
      if echo "${PARSED}" | jq -e 'type == "array"' >/dev/null 2>&1; then
        EXISTING_PRODUCTS="${PARSED}"
      fi
    fi
  # Check if it's a direct JSON array (response body is the value itself)
  elif echo "${PRODUCTS_RESPONSE}" | jq -e 'type == "array"' >/dev/null 2>&1; then
    EXISTING_PRODUCTS="${PRODUCTS_RESPONSE}"
  # Check if it's a JSON string that needs parsing
  elif echo "${PRODUCTS_RESPONSE}" | jq -e 'type == "string"' >/dev/null 2>&1; then
    STRING_VALUE=$(echo "${PRODUCTS_RESPONSE}" | jq -r '.')
    PARSED=$(echo "${STRING_VALUE}" | jq -e '.' 2>/dev/null || echo "[]")
    if echo "${PARSED}" | jq -e 'type == "array"' >/dev/null 2>&1; then
      EXISTING_PRODUCTS="${PARSED}"
    fi
  fi
fi

echo "Debug: Found $(echo "${EXISTING_PRODUCTS}" | jq 'length') existing products"

# Ensure we have a valid JSON array
if ! echo "${EXISTING_PRODUCTS}" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "Warning: Existing products list is invalid, starting with empty array"
  EXISTING_PRODUCTS="[]"
fi

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

