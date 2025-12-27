#!/bin/bash
set -euo pipefail

# Script to batch build multiple Talos versions
# Usage: ./scripts/build-versions.sh [version1] [version2] ...

# If no versions provided, use a reasonable default set
if [ $# -eq 0 ]; then
  echo "No versions provided. Fetching recent stable versions..."
  VERSIONS=$(curl -s "https://api.github.com/repos/siderolabs/talos/releases" | \
    jq -r '.[] | select(.tag_name | test("^v1\\.(10|11|12)\\.[0-9]+$")) | .tag_name' | \
    sort -V | tail -10 | tr '\n' ' ')
  echo "Will build: ${VERSIONS}"
  read -p "Continue? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
  VERSIONS_ARRAY=($VERSIONS)
else
  VERSIONS_ARRAY=("$@")
fi

echo "Building ${#VERSIONS_ARRAY[@]} versions..."

for version in "${VERSIONS_ARRAY[@]}"; do
  version=$(echo "$version" | tr -d ' ')
  if [ -z "$version" ]; then
    continue
  fi
  
  echo ""
  echo "=========================================="
  echo "Building version: ${version}"
  echo "=========================================="
  
  # Check if release already exists
  if gh release view "${version}" >/dev/null 2>&1; then
    echo "⚠️  Release ${version} already exists, skipping..."
    continue
  fi
  
  # Trigger workflow_dispatch
  echo "Triggering workflow for ${version}..."
  gh workflow run ci.yml \
    --ref main \
    -f version="${version}" || {
    echo "❌ Failed to trigger workflow for ${version}"
    continue
  }
  
  echo "✓ Workflow triggered for ${version}"
  
  # Small delay to avoid rate limiting
  sleep 2
done

echo ""
echo "=========================================="
echo "Done! Triggered builds for all versions."
echo "Monitor progress at: https://github.com/$(gh repo view --json owner,name -q '.owner.login + "/" + .name')/actions"
echo "=========================================="

