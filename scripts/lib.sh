#!/bin/bash
# Helpers shared by the build and release scripts. Source this file; do not run it.

# Image Factory schematic with no customization (no extensions, no extra kernel args).
# The ID is the hash of `customization: {}`, returned by POST https://factory.talos.dev/schematics.
TALOS_FACTORY_SCHEMATIC="376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"

# variant_prefix prints the release asset prefix for a variant. The default
# variant keeps the bare `talos` prefix so existing asset names do not change.
variant_prefix() {
  if [ "$1" = "default" ]; then
    echo "talos"
  else
    echo "talos-$1"
  fi
}

# variant_files prints the metadata tarball and disk image names for a variant and arch.
variant_files() {
  local prefix
  prefix="$(variant_prefix "$1")"
  echo "${prefix}-$2-incus.tar.xz"
  echo "${prefix}-$2.qcow2"
}

# upstream_image_url prints the URL of the zstd-compressed raw disk for a variant.
# The Talos GitHub release ships only the metal disk. Other platforms come from Image Factory.
upstream_image_url() {
  local variant="$1" version="$2" arch="$3"
  case "${variant}" in
    default)
      echo "https://github.com/siderolabs/talos/releases/download/${version}/metal-${arch}.raw.zst"
      ;;
    nocloud)
      echo "https://factory.talos.dev/image/${TALOS_FACTORY_SCHEMATIC}/${version}/nocloud-${arch}.raw.zst"
      ;;
    *)
      echo "Error: unknown variant ${variant}" >&2
      return 1
      ;;
  esac
}
