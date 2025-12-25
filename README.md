# Talos OS Unified Images for Incus

Automatically builds and releases unified Incus images from Talos OS releases.

## Usage

```bash
# Import and launch from GitHub release
incus image import https://github.com/windsorcli/talos-incus/releases/download/v1.11.6/incus-amd64.tar.gz --alias talos-v1.11.6-amd64
incus launch talos-v1.11.6-amd64 my-instance

# Or launch directly from URL
incus launch https://github.com/windsorcli/talos-incus/releases/download/v1.11.6/incus-amd64.tar.gz my-instance
```

## How It Works

Renovate tracks Talos releases and automatically updates the version in `.github/workflows/build-release.yml`. When the version changes, the workflow builds unified images for `amd64` and `arm64` and creates a GitHub release.

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
   gpg --verify incus-amd64.tar.gz.asc incus-amd64.tar.gz
   gpg --verify incus-arm64.tar.gz.asc incus-arm64.tar.gz
   ```

