# xremap DEB Packages for Debian and Ubuntu

This repository contains the Debian packaging scripts for [xremap](https://github.com/xremap/xremap), a key remapper for Linux supporting app-specific remapping and Wayland.

Packages are built for **amd64** and **arm64** on a Debian 12 baseline, so they work on Debian 12+, Ubuntu 22.04+, and derivatives such as Pop!\_OS and Linux Mint.

This is the Debian/Ubuntu counterpart of [xremap-fedora](https://github.com/BlakeGardner/xremap-fedora), which distributes RPMs via COPR.

## Installation Instructions

The packages are distributed via an apt repository hosted on GitHub Pages.

```bash
# Add the signing key
curl -fsSL https://blakegardner.github.io/xremap-debian/xremap-archive-keyring.gpg | \
  sudo tee /usr/share/keyrings/xremap-archive-keyring.gpg > /dev/null

# Add the repository
echo "deb [signed-by=/usr/share/keyrings/xremap-archive-keyring.gpg] https://blakegardner.github.io/xremap-debian stable main" | \
  sudo tee /etc/apt/sources.list.d/xremap.list

# Install a variant
sudo apt update
sudo apt install xremap-gnome
```

Alternatively, download a `.deb` from the [releases page](https://github.com/BlakeGardner/xremap-debian/releases) and install it with `sudo apt install ./xremap-gnome_*.deb`.

## Available Variants

Due to differences in how application specific remapping is implemented in different desktop environments, multiple variants of `xremap` are available. Choose the variant that best matches your desktop environment.

- **Vanilla (`xremap`)**: Use this variant if you're unsure which one to choose.
- **GNOME (`xremap-gnome`)**: This variant is recommended if you want application-specific remapping to work in GNOME.
- **KDE (`xremap-kde`)**: This variant is recommended if you want application-specific remapping to work in KDE Plasma.
- **wlroots (`xremap-wlroots`)**: This variant is recommended if you're using a wlroots-based compositor like Sway.
- **Hyprland (`xremap-hypr`)**: This variant is specifically built for Hyprland compositor.
- **Niri (`xremap-niri`)**: This variant is specifically built for Niri compositor.
- **COSMIC (`xremap-cosmic`)**: This variant is specifically built for System76's COSMIC desktop.
- **X11 (`xremap-x11`)**: This variant is recommended if you're using an X11-based desktop environment.
- **Socket (`xremap-socket`)**: This variant is built with socket client support and logind session monitor.

**Note:** Only one variant can be installed at a time.

## Switching Between Variants

To switch between different variants of `xremap`, install the new variant directly — apt resolves the conflict and replaces the old one:

```bash
sudo apt install xremap-kde
```

Each variant registers itself as `/usr/bin/xremap` through the `update-alternatives` system.

## Permissions and Udev Rules

### Input Group

The package creates an `input` group if it doesn't exist. You need to add your user to this group to allow `xremap` to access input devices.

```bash
sudo usermod -aG input $USER
```

Log out and log back in for the group changes to take effect.

### Udev Rules

A udev rules file is installed at `/usr/lib/udev/rules.d/00-xremap-input.rules` to set the appropriate permissions on input devices.

## Building Locally

```bash
# Build every variant (requires cargo, dpkg-deb, curl)
./scripts/build-debs.sh

# Build a subset
VARIANTS="vanilla gnome" ./scripts/build-debs.sh
```

The built packages are placed in `dist/`.

## Releasing a New Version

When upstream [xremap](https://github.com/xremap/xremap/releases) publishes a new version:

```bash
# 1. Update the version files
echo "0.15.10" > VERSION   # the new upstream version (without the leading v)
echo "1" > DEB_REVISION    # always reset to 1 for a new upstream version

# 2. (Optional) Verify the build locally before releasing
./scripts/build-debs.sh

# 3. Commit and push
git add VERSION DEB_REVISION
git commit -m "Update xremap to upstream version 0.15.10"
git push

# 4. Publish a GitHub release tagged v<version> — this triggers the build
gh release create v0.15.10 --title "xremap 0.15.10" --notes \
  "Debian/Ubuntu packages for xremap upstream version 0.15.10."
```

Publishing the release triggers the [deb workflow](.github/workflows/deb.yml), which automatically:

1. Builds all nine variants for amd64 and arm64 in a Debian 12 container.
2. Attaches the 18 `.deb` files to the GitHub release.
3. Regenerates and signs the apt repository, and publishes it to the `gh-pages` branch (served by GitHub Pages).

No manual steps are needed after publishing the release. Monitor progress with:

```bash
gh run watch --repo BlakeGardner/xremap-debian
```

### Verifying a Release

```bash
# All 18 assets attached to the release
gh release view v0.15.10 --json assets --jq '.assets | length'

# apt repo serves the new version with a valid signature
curl -fsSL https://blakegardner.github.io/xremap-debian/dists/stable/main/binary-amd64/Packages | grep -A1 '^Package: xremap$'
```

### Re-releasing a Packaging Fix

If the packaging itself needs a fix (build script, udev rule, maintainer scripts) without a new upstream version, bump [DEB_REVISION](DEB_REVISION) instead (e.g. `1` → `2`), commit, and publish a release tagged with a suffix, e.g. `v0.15.10-2`. The packages will carry the version `0.15.10-2`.

## One-Time Setup

These are already configured for this repository and only need to be repeated if it is recreated:

1. **GitHub Pages**: enabled from the `gh-pages` branch (root path). The workflow creates the branch on its first run:
   ```bash
   gh api repos/BlakeGardner/xremap-debian/pages -X POST -f "source[branch]=gh-pages" -f "source[path]=/"
   ```
2. **Signing key**: a dedicated, passphrase-less GPG key used only for signing this apt repository:
   ```bash
   gpg --batch --gen-key <<'EOF'
   %no-protection
   Key-Type: eddsa
   Key-Curve: ed25519
   Key-Usage: sign
   Name-Real: xremap apt repository
   Name-Email: blakerg@gmail.com
   Expire-Date: 0
   %commit
   EOF
   ```
3. **Repository secret** `APT_GPG_PRIVATE_KEY`: the armored private key, used by the workflow to sign the apt repository metadata:
   ```bash
   gpg --armor --export-secret-keys <KEY_ID> | gh secret set APT_GPG_PRIVATE_KEY --repo BlakeGardner/xremap-debian
   ```
   Keep a backup of the private key somewhere safe (e.g. a password manager). If the key is ever lost or rotated, users must re-import the new public key from `xremap-archive-keyring.gpg`.
