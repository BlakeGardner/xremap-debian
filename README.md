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

1. Update the upstream version in [VERSION](VERSION) (and reset [DEB_REVISION](DEB_REVISION) to `1`).
2. Commit and push, then publish a GitHub release tagged `v<version>`.
3. The [deb workflow](.github/workflows/deb.yml) builds the packages, attaches them to the release, and updates the apt repository on the `gh-pages` branch.

### Repository Secrets

The workflow requires one secret:

- `APT_GPG_PRIVATE_KEY`: an armored GPG private key (`gpg --armor --export-secret-keys <key-id>`) used to sign the apt repository metadata.
