# Talos OS Images for Incus

This repository automatically converts [Talos OS](https://www.talos.dev/) disk images into Incus-compatible virtual machine images. Talos is a minimal, immutable Linux distribution designed for Kubernetes, but its official releases don't include Incus/LXD-compatible formats.

> **⚠️ Caution: Not an Authoritative Source**
>
> This image source is a community-driven project and is **not maintained or endorsed by SideroLabs or the Talos OS team**. Although we strive to provide accurate and timely images, **they are provided on a "best effort" basis and are not guaranteed for production use**.
>
> **Do NOT use these images in critical or production environments.** They are intended only for development, testing, or personal experimentation until an official simplestreams (or LXD/Incus) image source is made available by Talos OS or Incus.
>
> If and when an officially supported source for Incus images becomes available, you should migrate to that.
>
---
## What This Repository Does

This repository sets up a simplestreams server that distributes Talos OS images for Incus. It automatically converts Talos releases into Incus-compatible VM images, signs them with cosign, and serves them via a Cloudflare Worker at `images.windsorcli.dev`.

> **Missing a version you need?**
>
> If there is a Talos OS version you want, but it isn't available through this repository or `images.windsorcli.dev`, please [file an issue](https://github.com/windsorcli/talos-incus/issues). Missing image versions can be built and published quickly upon request.

## Usage

```bash
# Use simplestreams remote (recommended)
incus remote add windsor https://images.windsorcli.dev --protocol simplestreams
incus image list windsor:
incus launch windsor:talos/v1.12.0/amd64 my-instance
```

If you are using the Incus Terraform provider, you can add remotes in the `provider` block:

```
# Configure Incus provider with remotes for image pulls
provider "incus" {
  remote {
    name     = "windsor"
    address  = "https://images.windsorcli.dev"
    protocol = "simplestreams"
    public   = true
  }
}

resource "incus_instance" "talos_controller" {
  name        = "talos-controller"
  description = "Talos control plane node"
  type        = "virtual-machine"
  image       = "windsor:talos/v1.12.0/arm64"
  ...
}
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

Releases are signed with [cosign](https://github.com/sigstore/cosign) using OIDC keyless signing. Signatures are created using the GitHub Actions workflow identity and stored in bundle format.

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