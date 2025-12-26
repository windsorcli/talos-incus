# Talos OS Images for Incus

This repository automatically converts [Talos OS](https://www.talos.dev/) disk images into Incus-compatible virtual machine images. Talos is a minimal, immutable Linux distribution designed for Kubernetes, but its official releases don't include Incus/LXD-compatible formats.

## What This Repository Does

This repository sets up a simplestreams server that distributes Talos OS images for Incus. It automatically converts Talos releases into Incus-compatible VM images, signs them with GPG, and serves them via a Cloudflare Worker at `images.windsorcli.dev`. When Talos releases a new version, this repo automatically builds and publishes the Incus-compatible images.

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
- Signs all files with GPG
- Releases them here

### Cloudflare Worker Proxy

Incus requires specific HTTP headers (`Incus-Image-Hash`, `Incus-Image-URL`) when importing images from URLs. Since GitHub Releases doesn't provide these headers, we use a Cloudflare Worker at `images.windsorcli.dev` that:

- Proxies requests to GitHub Releases
- Looks up pre-calculated SHA256 hashes
- Adds the required Incus headers
- Enables direct URL imports without manual downloads

## Signing

Releases are signed with GPG for verification.

**Public Key:**
- **Fingerprint**: `C398 9FD8 F4E4 F1DE B911 5A13 9F45 D7E6 57E6 6BC0`
- **Key ID**: `9F45D7E657E66BC0`
- **Email**: `windsor-release-managers@googlegroups.com`

**Verify Signatures:**

1. Import the public key:
   ```bash
   gpg --keyserver keys.openpgp.org --recv-keys 9F45D7E657E66BC0
   ```

2. Download the signature file from the release (`.asc` file)

3. Verify metadata files:
   ```bash
   gpg --verify talos-amd64-incus.tar.xz.asc talos-amd64-incus.tar.xz
   gpg --verify talos-arm64-incus.tar.xz.asc talos-arm64-incus.tar.xz
   ```

4. Verify disk files:
   ```bash
   gpg --verify talos-amd64.qcow2.asc talos-amd64.qcow2
   gpg --verify talos-arm64.qcow2.asc talos-arm64.qcow2
   ```