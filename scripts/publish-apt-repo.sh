#!/usr/bin/env bash
#
# Generate (or update) a flat signed apt repository from built .deb files.
# The resulting directory is intended to be published on GitHub Pages.
#
# Usage:
#   ./scripts/publish-apt-repo.sh <deb-dir> <repo-dir>
#
#   <deb-dir>   directory containing the freshly built .deb files
#   <repo-dir>  output directory for the apt repository (existing pool/ contents
#               are preserved, so older package versions stay installable)
#
# Environment:
#   GPG_KEY_ID  key id/fingerprint/email used to sign the Release file (required
#               unless SKIP_SIGN=1)
#   SKIP_SIGN   set to 1 to skip GPG signing (for local testing)
#   ARCHS       architectures to index (default: "amd64 arm64")
#
set -euo pipefail

DEB_DIR="${1:?usage: publish-apt-repo.sh <deb-dir> <repo-dir>}"
REPO_DIR="${2:?usage: publish-apt-repo.sh <deb-dir> <repo-dir>}"
ARCHS="${ARCHS:-amd64 arm64}"
SUITE="stable"
COMPONENT="main"

command -v apt-ftparchive >/dev/null || {
    echo "error: apt-ftparchive not found (install apt-utils)" >&2
    exit 1
}

mkdir -p "$REPO_DIR/pool/$COMPONENT"
cp -v "$DEB_DIR"/*.deb "$REPO_DIR/pool/$COMPONENT/"

cd "$REPO_DIR"

for arch in $ARCHS; do
    mkdir -p "dists/$SUITE/$COMPONENT/binary-$arch"
    apt-ftparchive --arch "$arch" packages pool \
        > "dists/$SUITE/$COMPONENT/binary-$arch/Packages"
    gzip -9 -n -c "dists/$SUITE/$COMPONENT/binary-$arch/Packages" \
        > "dists/$SUITE/$COMPONENT/binary-$arch/Packages.gz"
done

apt-ftparchive \
    -o "APT::FTPArchive::Release::Origin=xremap" \
    -o "APT::FTPArchive::Release::Label=xremap" \
    -o "APT::FTPArchive::Release::Suite=$SUITE" \
    -o "APT::FTPArchive::Release::Codename=$SUITE" \
    -o "APT::FTPArchive::Release::Components=$COMPONENT" \
    -o "APT::FTPArchive::Release::Architectures=$ARCHS" \
    -o "APT::FTPArchive::Release::Description=xremap Debian/Ubuntu packages" \
    release "dists/$SUITE" > "dists/$SUITE/Release"

if [ "${SKIP_SIGN:-0}" != "1" ]; then
    : "${GPG_KEY_ID:?GPG_KEY_ID must be set unless SKIP_SIGN=1}"
    gpg --batch --yes -u "$GPG_KEY_ID" \
        --armor --detach-sign --output "dists/$SUITE/Release.gpg" "dists/$SUITE/Release"
    gpg --batch --yes -u "$GPG_KEY_ID" \
        --armor --clearsign --output "dists/$SUITE/InRelease" "dists/$SUITE/Release"
    # Export the public key so users can fetch it from the repo itself
    gpg --export "$GPG_KEY_ID" > xremap-archive-keyring.gpg
fi

echo "==> apt repository generated in $REPO_DIR"
