#!/usr/bin/env bash
#
# Build xremap .deb packages for all variants.
#
# Usage:
#   ./scripts/build-debs.sh
#
# Environment overrides:
#   VERSION       xremap upstream version (default: contents of VERSION file)
#   DEB_REVISION  Debian package revision  (default: contents of DEB_REVISION file)
#   VARIANTS      space-separated list of variants to build (default: all)
#   OUTPUT_DIR    where to place the built .deb files (default: ./dist)
#   BUILD_DIR     scratch build directory (default: ./build)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION="${VERSION:-$(cat "$REPO_ROOT/VERSION")}"
DEB_REVISION="${DEB_REVISION:-$(cat "$REPO_ROOT/DEB_REVISION")}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/dist}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
ARCH="$(dpkg --print-architecture)"
MAINTAINER="Blake Gardner <blakerg@gmail.com>"
HOMEPAGE="https://github.com/xremap/xremap"

# variant -> cargo features ("" = vanilla build with default features)
declare -A FEATURES=(
    [vanilla]=""
    [gnome]="gnome"
    [x11]="x11"
    [kde]="kde"
    [wlroots]="wlroots"
    [hypr]="hypr"
    [niri]="niri"
    [cosmic]="cosmic"
    [socket]="socket"
)

# variant -> package name
declare -A PKGNAME=(
    [vanilla]="xremap"
    [gnome]="xremap-gnome"
    [x11]="xremap-x11"
    [kde]="xremap-kde"
    [wlroots]="xremap-wlroots"
    [hypr]="xremap-hypr"
    [niri]="xremap-niri"
    [cosmic]="xremap-cosmic"
    [socket]="xremap-socket"
)

# variant -> extra description line
declare -A VARIANT_DESC=(
    [vanilla]="This is the vanilla variant without desktop-specific support."
    [gnome]="This variant is built with GNOME Wayland support."
    [x11]="This variant is built with X11 support."
    [kde]="This variant is built with KDE Plasma Wayland support."
    [wlroots]="This variant is built with wlroots support for compositors like Sway."
    [hypr]="This variant is built with Hyprland support."
    [niri]="This variant is built with Niri support."
    [cosmic]="This variant is built with COSMIC Wayland support (System76's COSMIC desktop)."
    [socket]="This variant is built with socket client support and logind session monitor."
)

# variant -> Recommends (desktop environment packages; soft dependency so that
# installation never fails on systems where the DE comes from another source)
declare -A RECOMMENDS=(
    [vanilla]=""
    [gnome]="gnome-shell"
    [x11]="xserver-xorg-core"
    [kde]="plasma-workspace"
    [wlroots]=""
    [hypr]="hyprland"
    [niri]="niri"
    [cosmic]="cosmic-session"
    [socket]=""
)

# variant -> update-alternatives priority (matches the Fedora spec)
declare -A PRIORITY=(
    [vanilla]=10
    [gnome]=20
    [x11]=20
    [kde]=20
    [wlroots]=20
    [hypr]=20
    [niri]=20
    [cosmic]=20
    [socket]=20
)

ALL_VARIANTS="vanilla gnome x11 kde wlroots hypr niri cosmic socket"
VARIANTS="${VARIANTS:-$ALL_VARIANTS}"

echo "==> Building xremap ${VERSION}-${DEB_REVISION} (${ARCH}) variants: ${VARIANTS}"

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# --- Fetch and extract upstream source -------------------------------------
TARBALL="$BUILD_DIR/xremap-$VERSION.tar.gz"
SRC_DIR="$BUILD_DIR/xremap-$VERSION"

if [ ! -f "$TARBALL" ]; then
    echo "==> Downloading xremap v$VERSION source"
    curl -fsSL -o "$TARBALL" \
        "https://github.com/xremap/xremap/archive/refs/tags/v$VERSION.tar.gz"
fi

if [ ! -d "$SRC_DIR" ]; then
    tar -xzf "$TARBALL" -C "$BUILD_DIR"
fi

# --- Build and package each variant -----------------------------------------
for variant in $VARIANTS; do
    pkg="${PKGNAME[$variant]}"
    features="${FEATURES[$variant]}"

    echo "==> Building variant: $variant (package: $pkg)"

    feature_args=()
    if [ -n "$features" ]; then
        feature_args=(--features "$features")
    fi
    (
        cd "$SRC_DIR"
        cargo build --release "${feature_args[@]}" --target-dir "target-$variant"
    )

    bin="$SRC_DIR/target-$variant/release/xremap"
    strip --strip-unneeded "$bin"

    # Compute the minimum glibc the binary actually requires
    glibc_min=$(objdump -T "$bin" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -V | tail -1)

    # --- Assemble package tree ---
    pkgroot="$BUILD_DIR/pkgroot-$variant"
    rm -rf "$pkgroot"
    mkdir -p \
        "$pkgroot/DEBIAN" \
        "$pkgroot/usr/bin" \
        "$pkgroot/usr/lib/udev/rules.d" \
        "$pkgroot/usr/share/doc/$pkg"

    install -m 0755 "$bin" "$pkgroot/usr/bin/xremap-$variant"
    install -m 0644 "$REPO_ROOT/00-xremap-input.rules" \
        "$pkgroot/usr/lib/udev/rules.d/00-xremap-input.rules"

    # Debian copyright file from the upstream MIT license
    {
        echo "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/"
        echo "Upstream-Name: xremap"
        echo "Source: $HOMEPAGE"
        echo
        echo "Files: *"
        echo "Copyright: Takashi Kokubun"
        echo "License: MIT"
        sed 's/^$/./; s/^/ /' "$SRC_DIR/LICENSE"
    } > "$pkgroot/usr/share/doc/$pkg/copyright"

    {
        echo "$pkg ($VERSION-$DEB_REVISION) unstable; urgency=medium"
        echo
        echo "  * Package xremap upstream version $VERSION."
        echo
        echo " -- $MAINTAINER  $(date -R)"
    } | gzip -9 -n > "$pkgroot/usr/share/doc/$pkg/changelog.Debian.gz"
    chmod 0644 "$pkgroot/usr/share/doc/$pkg/copyright" \
        "$pkgroot/usr/share/doc/$pkg/changelog.Debian.gz"

    # Conflicts/Replaces with every other variant so only one can be installed
    conflicts=""
    for other in $ALL_VARIANTS; do
        if [ "$other" != "$variant" ]; then
            conflicts="${conflicts:+$conflicts, }${PKGNAME[$other]}"
        fi
    done

    # --- Control file ---
    {
        echo "Package: $pkg"
        echo "Version: $VERSION-$DEB_REVISION"
        echo "Architecture: $ARCH"
        echo "Maintainer: $MAINTAINER"
        echo "Section: utils"
        echo "Priority: optional"
        echo "Homepage: $HOMEPAGE"
        echo "Depends: libc6 (>= $glibc_min)"
        if [ -n "${RECOMMENDS[$variant]}" ]; then
            echo "Recommends: ${RECOMMENDS[$variant]}"
        fi
        echo "Conflicts: $conflicts"
        echo "Replaces: $conflicts"
        echo "Description: key remapper for Linux with app-specific remapping and Wayland support"
        echo " xremap is a key remapper for Linux. It supports application-specific"
        echo " remapping and Wayland."
        echo " ."
        echo " ${VARIANT_DESC[$variant]}"
    } > "$pkgroot/DEBIAN/control"

    # --- Maintainer scripts ---
    cat > "$pkgroot/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e

if [ "\$1" = "configure" ]; then
    # Create 'input' group if it doesn't exist
    getent group input >/dev/null || addgroup --system input

    update-alternatives --install /usr/bin/xremap xremap \\
        /usr/bin/xremap-$variant ${PRIORITY[$variant]}

    # Reload udev rules so the uinput permissions take effect
    if command -v udevadm >/dev/null 2>&1; then
        udevadm control --reload-rules >/dev/null 2>&1 || true
        udevadm trigger --subsystem-match=misc --attr-match=name=uinput >/dev/null 2>&1 || true
    fi
fi

exit 0
EOF

    cat > "$pkgroot/DEBIAN/prerm" <<EOF
#!/bin/sh
set -e

if [ "\$1" = "remove" ]; then
    update-alternatives --remove xremap /usr/bin/xremap-$variant
fi

exit 0
EOF

    chmod 0755 "$pkgroot/DEBIAN/postinst" "$pkgroot/DEBIAN/prerm"
    find "$pkgroot" -type d -exec chmod 0755 {} +

    # --- Build the .deb ---
    deb="$OUTPUT_DIR/${pkg}_${VERSION}-${DEB_REVISION}_${ARCH}.deb"
    dpkg-deb --build --root-owner-group -Zxz "$pkgroot" "$deb"
    echo "==> Built $deb"
done

echo "==> All done. Packages in $OUTPUT_DIR:"
ls -la "$OUTPUT_DIR"
