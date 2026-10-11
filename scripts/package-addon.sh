#!/usr/bin/env bash
# Package the addon under WoWErrands/ so players can extract it into AddOns/.
set -euo pipefail

version="${1:?Usage: bash scripts/package-addon.sh 2.0.0}"
if [[ -f WoWErrands.toc ]]; then
  addon_root="."
elif [[ -f WoWErrands/WoWErrands.toc ]]; then
  addon_root="WoWErrands"
else
  echo "ERROR: WoWErrands.toc was not found"
  exit 1
fi

mkdir -p dist
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/WoWErrands"

# Include addon code and assets, but not Git metadata, workflows or source docs.
rsync -a \
  --exclude='.git/' \
  --exclude='.github/' \
  --exclude='.gitignore' \
  --exclude='.vscode/' \
  --exclude='.editorconfig' \
  --exclude='scripts/' \
  --exclude='tests/' \
  --exclude='dist/' \
  --exclude='README.md' \
  --exclude='CHANGELOG.md' \
  --exclude='*.zip' \
  "$addon_root/" "$tmp/WoWErrands/"

archive="$(pwd)/dist/WoWErrands-${version}.zip"
(cd "$tmp" && zip -qr "$archive" WoWErrands)

echo "Created $archive"
unzip -l "$archive"
