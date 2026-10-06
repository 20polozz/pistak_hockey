#!/usr/bin/env bash
# Commits build/web_deploy (pruned web build, see tool/build_web.sh) to the
# `web` branch WITHOUT checking it out. Cloudflare Pages deploys that branch.
set -euo pipefail
cd "$(dirname "$0")/.."
src=build/web_deploy
[[ -f $src/index.html ]] || { echo "missing $src"; exit 1; }
idx=$(mktemp -u)  # must not exist yet (git creates it)
GIT_INDEX_FILE=$idx git --work-tree="$src" add -A .
tree=$(GIT_INDEX_FILE=$idx git write-tree)
rm -f "$idx"
parent=$(git rev-parse -q --verify refs/heads/web || true)
if [[ -n $parent && $(git rev-parse "$parent^{tree}") == "$tree" ]]; then
  echo "web branch already up to date"; exit 0
fi
version=$(grep '^version:' pubspec.yaml | awk '{print $2}')
msg="web $version (from $(git rev-parse --short HEAD))"
commit=$(git commit-tree "$tree" ${parent:+-p "$parent"} -m "$msg")
git update-ref refs/heads/web "$commit"
echo "web -> $commit ($msg)"
