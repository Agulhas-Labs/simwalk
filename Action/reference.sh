#!/bin/sh
#
# Finds the reference bundle: the newest unexpired artifact named SIMWALK_REFERENCE_ARTIFACT whose
# workflow run's head branch is the pull request's base and ran in this repository (not a fork), downloaded to $SIMWALK_OUT/reference.simwalk.
# No reference is a stated outcome, not a failure: it writes $SIMWALK_OUT/no-reference with the reason.
# Inputs: SIMWALK_OUT, SIMWALK_REFERENCE_ARTIFACT, GITHUB_REPOSITORY, GITHUB_EVENT_NAME, GITHUB_BASE_REF,
# SIMWALK_DEFAULT_BRANCH (named in the message; references are uploaded only by runs on it).

set -eu

out=${SIMWALK_OUT:?}
mkdir -p "$out"

if [ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]; then
  echo "not a pull request; no reference to compare against"
  exit 0
fi

base=${GITHUB_BASE_REF:?}
name=${SIMWALK_REFERENCE_ARTIFACT:-simwalk-reference}
repo=${GITHUB_REPOSITORY:?}
default=${SIMWALK_DEFAULT_BRANCH:-the default branch}

none() {
  printf '%s\n' "$1" >"$out/no-reference"
  echo "$1"
  exit 0
}

query=$(jq -rn --arg v "$name" '$v|@uri')
listing=$(gh api "repos/$repo/actions/artifacts?name=$query&per_page=100") ||
  none "no reference on $base yet; the artifact list could not be read"
id=$(printf '%s' "$listing" | jq -r --arg base "$base" \
  '[.artifacts[] | select(.expired == false and .workflow_run.head_branch == $base
     and .workflow_run.head_repository_id == .workflow_run.repository_id)]
   | sort_by(.created_at) | last | .id // empty')
[ -n "$id" ] || none "no reference on $base yet; references come from runs on $default"

zip="$out/reference.zip"
if ! gh api "repos/$repo/actions/artifacts/$id/zip" >"$zip"; then
  none "no reference on $base yet; artifact $id could not be downloaded"
fi
mkdir -p "$out/reference.simwalk"
if ! unzip -q "$zip" -d "$out/reference.simwalk"; then
  rm -rf "$out/reference.simwalk"
  none "no reference on $base yet; artifact $id is not a readable archive"
fi
rm -f "$zip"
echo "reference: artifact $id from $base"
