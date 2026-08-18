#!/usr/bin/env bash
# Backfill releases for upstream xremap versions newer than the packaged VERSION.
#
# For each missing version (oldest -> newest) this script:
#   1. Updates VERSION (and resets DEB_REVISION to 1), commits and pushes to main.
#   2. Creates the GitHub release v<version>, which triggers the deb workflow.
#   3. Waits for the deb workflow run to succeed before moving to the next
#      version (the apt-repo publish step must not run concurrently).
#
# Requirements: gh (authenticated), git push access, a clean checkout of main.
#
# Usage: ./scripts/backfill-releases.sh

set -euo pipefail

repo="BlakeGardner/xremap-debian"
upstream_repo="xremap/xremap"

branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" != "main" ]; then
    echo "Error: run this from the main branch (currently on $branch)." >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "Error: working tree is not clean." >&2
    exit 1
fi
git pull --ff-only

current=$(cat VERSION)
echo "Current packaged version: $current"

# Upstream stable versions newer than the current one, oldest first.
mapfile -t missing < <(
    gh api "repos/$upstream_repo/releases?per_page=100" \
        --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' |
        sed 's/^v//' |
        sort -V |
        awk -v cur="$current" 'found { print } $0 == cur { found = 1 }'
)

if [ "${#missing[@]}" -eq 0 ]; then
    echo "No missing versions — nothing to backfill."
    exit 0
fi

echo "Versions to backfill (${#missing[@]}): ${missing[*]}"

for version in "${missing[@]}"; do
    echo
    echo "=== Backfilling $version ==="

    if gh release view "v$version" --repo "$repo" > /dev/null 2>&1; then
        echo "Release v$version already exists — skipping."
        continue
    fi

    echo "$version" > VERSION
    echo "1" > DEB_REVISION
    git add VERSION DEB_REVISION
    git commit -m "Update xremap to upstream version $version"
    git push
    sha=$(git rev-parse HEAD)

    gh release create "v$version" --repo "$repo" \
        --title "xremap $version" \
        --notes "Debian/Ubuntu packages for xremap upstream version $version."

    echo "Waiting for the deb workflow run for $sha to start..."
    run_id=""
    for _ in $(seq 1 30); do
        run_id=$(gh run list --repo "$repo" --workflow deb.yml --event release \
            --json databaseId,headSha \
            --jq ".[] | select(.headSha == \"$sha\") | .databaseId" | head -n1)
        [ -n "$run_id" ] && break
        sleep 10
    done
    if [ -z "$run_id" ]; then
        echo "Error: no deb workflow run appeared for v$version." >&2
        exit 1
    fi

    echo "Watching run $run_id for v$version..."
    gh run watch "$run_id" --repo "$repo" --exit-status --interval 30
    echo "v$version built and published."
done

echo
echo "Backfill complete."
