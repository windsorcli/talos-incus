# Talos OS Unified Images for Incus

Automatically builds and releases unified Incus images from Talos OS releases.

## Usage

```bash
# Import and launch from images.windsorcli.dev (recommended)
incus image import https://images.windsorcli.dev/talos-incus/v1.12.0/incus-amd64.tar.xz --alias talos-v1.12.0-amd64
incus launch talos-v1.12.0-amd64 my-instance

# Or launch directly from URL
incus launch https://images.windsorcli.dev/talos-incus/v1.12.0/incus-amd64.tar.xz my-instance

# Or use simplestreams remote (after adding: incus remote add talos https://images.windsorcli.dev --protocol simplestreams)
incus image list talos:
incus launch talos:talos/v1.12.0/amd64 my-instance
```

## How It Works

This repository automatically builds Incus images directly from [Talos OS releases](https://github.com/siderolabs/talos). When a new Talos version is released, Renovate automatically updates the version and triggers a build that:

- Downloads the official Talos disk images from `siderolabs/talos`
- Converts them to the unified Incus format
- Signs them with GPG
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

3. Verify:
   ```bash
   gpg --verify incus-amd64.tar.xz.asc incus-amd64.tar.xz
   gpg --verify incus-arm64.tar.xz.asc incus-arm64.tar.xz
   ```