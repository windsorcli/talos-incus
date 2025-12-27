# Talos OS Images for Incus

This repository provides a simplestreams server that makes [Talos OS](https://www.talos.dev/) images available for Incus. Talos is a minimal, immutable Linux distribution designed for Kubernetes, but its official releases don't include Incus/LXD-compatible simplestreams formats.

> **ℹ️ About This Service**
>
> **Disk Images:** qcow2 disk images are proxied directly from the [official Talos image factory](https://factory.talos.dev), ensuring you receive authentic, unmodified Talos images.
>
> **Metadata Layer:** The Incus metadata (simplestreams format) is community-provided and maintained by this project. This repository is not officially maintained or endorsed by SideroLabs or the Talos OS team.
>
> As a community project, this service is provided on a "best effort" basis. Metadata files are signed with cosign for verification.
>
> If and when an officially supported simplestreams source for Incus images becomes available, you should consider migrating to that.
>
---
## What This Repository Does

This repository sets up a simplestreams server that distributes Talos OS images for Incus. It creates Incus-compatible metadata, proxies qcow2 disk images from the official Talos image factory, signs metadata with cosign, and serves everything via a Cloudflare Worker at `images.windsorcli.dev`.

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

This repository automatically creates Incus metadata for Talos OS images. When a new Talos version is released, Renovate automatically updates the version and triggers a build that:

- Creates Incus-compatible metadata tarballs
- Fetches qcow2 disk images from [Talos image factory](https://factory.talos.dev)
- Signs metadata files with cosign
- Stores metadata in Cloudflare KV for simplestreams serving

### Cloudflare Worker Proxy

Incus requires specific HTTP headers (`Incus-Image-Hash`, `Incus-Image-URL`) when importing images from URLs. We use a Cloudflare Worker at `images.windsorcli.dev` that:

- Proxies metadata requests to GitHub Releases
- Proxies qcow2 disk requests to Talos image factory (https://factory.talos.dev)
- Looks up pre-calculated SHA256 hashes from KV
- Adds the required Incus headers
- Enables direct URL imports without manual downloads

## Signing

Metadata files are signed with [cosign](https://github.com/sigstore/cosign) using OIDC keyless signing. Signatures are created using the GitHub Actions workflow identity and stored in bundle format.

**Note:** qcow2 disk images are proxied from Talos image factory and are not signed by this repository.

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

2. Download the metadata artifact and bundle file from the release

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