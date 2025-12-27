# Talos OS Images for Incus

This repository automatically converts [Talos OS](https://www.talos.dev/) disk images into Incus-compatible virtual machine images. Talos is a minimal, immutable Linux distribution designed for Kubernetes, but its official releases don't include Incus/LXD-compatible formats.

## What This Repository Does

This repository sets up a simplestreams server that distributes Talos OS images for Incus. It automatically converts Talos releases into Incus-compatible VM images, signs them with cosign, and serves them via a Cloudflare Worker at `images.windsorcli.dev`.

## Usage

```bash
# Use simplestreams remote (recommended)
incus remote add windsor https://images.windsorcli.dev --protocol simplestreams
incus image list windsor:
incus launch windsor:talos/v1.12.0/amd64 my-instance

# Or import split format files directly from GitHub releases
# Note: You need both the metadata and disk files
incus image import talos-amd64-incus.tar.xz talos-amd64.qcow2 --alias talos-v1.12.0-amd64
incus launch talos-v1.12.0-amd64 my-instance
```

## How It Works

This repository automatically builds Incus images directly from [Talos OS releases](https://github.com/siderolabs/talos). When a new Talos version is released, Renovate automatically updates the version and triggers a build that:

- Downloads the official Talos disk images from `siderolabs/talos`
- Converts them to split-format Incus images (metadata + disk files)
- Signs all files with cosign (OIDC keyless)
- Releases them here

### Cloudflare Worker Proxy

Incus requires specific HTTP headers (`Incus-Image-Hash`, `Incus-Image-URL`) when importing images from URLs. Since GitHub Releases doesn't provide these headers, we use a Cloudflare Worker at `images.windsorcli.dev` that:

- Proxies requests to GitHub Releases
- Looks up pre-calculated SHA256 hashes
- Adds the required Incus headers
- Enables direct URL imports without manual downloads

## Signing

Releases are signed with [cosign](https://github.com/sigstore/cosign) using OIDC keyless signing (same as upstream Talos). Signatures are created using the GitHub Actions workflow identity and stored in bundle format.

**Verify Signatures:**

1. Install cosign:
   ```bash
   # macOS
   brew install cosign
   
   # Linux
   wget -O cosign https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
   chmod +x cosign
   sudo mv cosign /usr/local/bin/
   ```

2. Download the artifact and bundle file from the release

3. Verify metadata files:
   ```bash
   cosign verify-blob \
     --bundle talos-amd64-incus.tar.xz.bundle \
     --certificate-identity-regexp '^https://github.com/windsorcli/talos-incus' \
     --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
     talos-amd64-incus.tar.xz
   
   cosign verify-blob \
     --bundle talos-arm64-incus.tar.xz.bundle \
     --certificate-identity-regexp '^https://github.com/windsorcli/talos-incus' \
     --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
     talos-arm64-incus.tar.xz
   ```

4. Verify disk files:
   ```bash
   cosign verify-blob \
     --bundle talos-amd64.qcow2.bundle \
     --certificate-identity-regexp '^https://github.com/windsorcli/talos-incus' \
     --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
     talos-amd64.qcow2
   
   cosign verify-blob \
     --bundle talos-arm64.qcow2.bundle \
     --certificate-identity-regexp '^https://github.com/windsorcli/talos-incus' \
     --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
     talos-arm64.qcow2
   ```