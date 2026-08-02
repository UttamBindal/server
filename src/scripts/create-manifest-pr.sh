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
base_branch="$(git remote show origin | awk -F': ' '/HEAD branch/ {print $2}' | tr -d '[:space:]')"
if [[ -z "$base_branch" ]]; then
  base_branch="main"
fi

git checkout -B "$branch_name"

"$repo_root/src/scripts/update-manifest.sh" "$image_tag"

version_tag="${image_tag##*:}"
version_no_v="${version_tag#v}"
if [[ "$version_tag" == "$version_no_v" ]]; then
  echo "Image tag does not include a leading v; updating VERSION to ${version_no_v}"
fi
if ! [[ "$version_no_v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Parsed version is invalid: $version_no_v"
  exit 1
fi

echo "$version_no_v" > "$repo_root/VERSION"

if git diff --quiet -- "$manifest_file" "$repo_root/VERSION"; then
  echo "No manifest or version changes to commit."
  exit 0
fi

git add "$manifest_file" "$repo_root/VERSION"
git commit -m "Update ArgoCD manifest and VERSION for image ${image_tag}"

git push -u origin "$branch_name" --force

pr_title="Update ArgoCD manifest to ${image_tag}"
pr_body="This pull request updates the ArgoCD manifest to use the newly published Docker image tag ${image_tag}."

pr_payload=$(PYTHONUTF8=1 PR_TITLE="$pr_title" PR_BODY="$pr_body" PR_HEAD="$branch_name" PR_BASE="$base_branch" python3 - <<'PY'
import json, os
print(json.dumps({
    'title': os.environ['PR_TITLE'],
    'body': os.environ['PR_BODY'],
    'head': os.environ['PR_HEAD'],
    'base': os.environ['PR_BASE']
}))
PY
)

auth_token="${PR_TOKEN:-$GITHUB_TOKEN}"
create_response=$(curl -sS -H "Authorization: Bearer $auth_token" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Content-Type: application/json" \
  https://api.github.com/repos/$GITHUB_REPOSITORY/pulls \
  -d "$pr_payload")

pr_number=$(python3 - <<'PY'
import json, sys
try:
    data = json.loads(sys.stdin.read() or '{}')
    print(data.get('number', ''))
except Exception:
    pass
PY
<<<"$create_response")

if [[ -z "$pr_number" ]]; then
  echo "PR creation response did not include a number, checking for an existing open PR..."
  owner="${GITHUB_REPOSITORY%%/*}"
  open_pr_response=$(curl -sS -H "Authorization: Bearer $auth_token" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls?state=open")
  pr_number=$(printf '%s' "$open_pr_response" | jq -r --arg owner "$owner" --arg branch "$branch_name" \
    '.[] | select(.head.repo.owner.login == $owner and .head.ref == $branch) | .number | tostring' | head -n 1)
fi

if [[ -z "$pr_number" ]]; then
  echo "Failed to find or create a PR. Response was:"
  echo "$create_response"
  exit 1
fi

echo "Using PR #$pr_number"

merge_response=$(curl -sS -X PUT -H "Authorization: Bearer $auth_token" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Content-Type: application/json" \
  https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$pr_number/merge \
  -d '{"merge_method":"merge"}')

echo "Merge response: $merge_response"
