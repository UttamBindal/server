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

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "GITHUB_REPOSITORY environment variable is required"
  exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" && -z "${PR_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN or PR_TOKEN environment variable is required"
  exit 1
fi

if [[ ! -f "$manifest_file" ]]; then
  echo "Manifest file not found: $manifest_file"
  exit 1
fi

branch_name="manifest-update-$(echo "$image_tag" | tr '/:' '--' | tr '.' '-')"
branch_name="$(echo "$branch_name" | sed -E 's/[^A-Za-z0-9._-]/-/g' | sed -E 's/^-+|[-.]+$//g')"

cd "$repo_root"

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

git fetch --all --tags

git checkout -B "$branch_name"

"$repo_root/src/scripts/update-manifest.sh" "$image_tag"

if git diff --quiet -- "$manifest_file"; then
  echo "No manifest changes to commit."
  exit 0
fi

git add "$manifest_file"
git commit -m "Update ArgoCD manifest for image ${image_tag}"

git push -u origin "$branch_name" --force

pr_title="Update ArgoCD manifest to ${image_tag}"
pr_body="This pull request updates the ArgoCD manifest to use the newly published Docker image tag ${image_tag}."

pr_payload=$(PYTHONUTF8=1 PR_TITLE="$pr_title" PR_BODY="$pr_body" PR_HEAD="$branch_name" python3 - <<'PY'
import json, os
print(json.dumps({
    'title': os.environ['PR_TITLE'],
    'body': os.environ['PR_BODY'],
    'head': os.environ['PR_HEAD'],
    'base': 'main'
}))
PY
)

auth_token="${PR_TOKEN:-$GITHUB_TOKEN}"
response=$(curl -sS -H "Authorization: Bearer $auth_token" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Content-Type: application/json" \
  https://api.github.com/repos/$GITHUB_REPOSITORY/pulls \
  -d "$pr_payload")

echo "$response"
