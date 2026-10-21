#!/bin/sh
#
# Walks, then diffs against the reference (when there is one) and audits. Never fails the step: each
# command's exit code goes to $SIMWALK_OUT/codes for verdict.sh, each answer to a text file for comment.sh.
# Inputs: SIMWALK_OUT, SIMWALK_WALKBOOK, SIMWALK_APP_PATH (optional), SIMWALK_LEASE_TOKEN.

set -u

out=${SIMWALK_OUT:?}
walkbook=${SIMWALK_WALKBOOK:?}
mkdir -p "$out"
: >"$out/codes"
run="$out/run.simwalk"

set -- walk "$walkbook" --output "$run" --lease "${SIMWALK_LEASE_TOKEN:?}"
if [ -n "${SIMWALK_APP_PATH:-}" ]; then
  set -- "$@" --app-path "$SIMWALK_APP_PATH"
fi
simwalk "$@" >"$out/walk.txt" 2>&1
walk_code=$?
echo "walk=$walk_code" >>"$out/codes"
cat "$out/walk.txt"

if [ ! -d "$run" ]; then
  echo "the walk filed no bundle; diff and audit skipped" | tee "$out/no-bundle"
  exit 0
fi

if [ -d "$out/reference.simwalk" ]; then
  simwalk bundle diff "$out/reference.simwalk" "$run" --crops "$out/crops" >"$out/diff.txt" 2>&1
  echo "diff=$?" >>"$out/codes"
  cat "$out/diff.txt"
fi

simwalk bundle audit "$run" >"$out/audit.txt" 2>&1
echo "audit=$?" >>"$out/codes"
cat "$out/audit.txt"
# Only an ok or qualified walk may become the next reference; a refused walk's partial bundle may not.
case "$walk_code" in
  0 | 2) echo "bundle=true" >>"${GITHUB_OUTPUT:-/dev/null}" ;;
esac
exit 0
