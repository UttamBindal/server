#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <image-tag>"
  exit 1
fi

image_tag="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
manifest_file="$repo_root/src/manifests/app.yaml"

if [[ ! -f "$manifest_file" ]]; then
  echo "Manifest file not found: $manifest_file"
  exit 1
fi

sed -E "s|image: .*|image: ${image_tag}|" "$manifest_file" > "$manifest_file.tmp"
mv "$manifest_file.tmp" "$manifest_file"
