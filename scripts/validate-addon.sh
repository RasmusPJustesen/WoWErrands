#!/usr/bin/env bash
# Validate WoWErrands addon manifests, referenced assets and Lua syntax.
set -euo pipefail

expected_version="${1:-}"
if [[ -f WoWErrands.toc ]]; then
  addon_root="."
elif [[ -f WoWErrands/WoWErrands.toc ]]; then
  addon_root="WoWErrands"
else
  echo "ERROR: Could not find WoWErrands.toc in the repository root or WoWErrands/"
  exit 1
fi

if [[ ! -f "$addon_root/WoWErrands.lua" ]]; then
  echo "ERROR: Missing WoWErrands.lua"
  exit 1
fi

for toc in WoWErrands.toc WoWErrands_Camelot.toc; do
  manifest="$addon_root/$toc"
  if [[ ! -f "$manifest" ]]; then
    echo "ERROR: Missing $manifest"
    exit 1
  fi

  toc_version="$(sed -n 's/^## Version:[[:space:]]*//p' "$manifest" | head -n 1 | tr -d '\r')"
  if [[ -z "$toc_version" ]]; then
    echo "ERROR: Missing ## Version in $manifest"
    exit 1
  fi
  if [[ -n "$expected_version" && "$toc_version" != "$expected_version" ]]; then
    echo "ERROR: $manifest has version $toc_version but tag expects $expected_version"
    exit 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ -z "${line//[[:space:]]/}" || "$line" == \#* ]]; then
      continue
    fi
    # WoW TOC files use backslashes for paths; on Linux the checkout uses /.
    referenced="${line//\\//}"
    if [[ ! -f "$addon_root/$referenced" ]]; then
      echo "ERROR: $manifest references missing file $referenced"
      exit 1
    fi
  done < "$manifest"
done

if command -v luac5.1 >/dev/null 2>&1; then
  while IFS= read -r -d '' file; do
    echo "Checking Lua syntax: $file"
    luac5.1 -p "$file"
  done < <(find "$addon_root" -type f -name '*.lua' \
    -not -path '*/.git/*' -not -path '*/.github/*' \
    -not -path '*/scripts/*' -not -path '*/tests/*' -print0)
else
  echo "Lua compiler not installed; skipping Lua syntax check locally. CI installs it."
fi

echo "WoWErrands validation passed."
