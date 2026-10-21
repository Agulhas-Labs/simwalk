#!/bin/sh
#
# Runs the action's scripts against stub `simwalk`, `gh`, `brew` executables placed first on PATH.
# Nothing here touches a simulator or the network. Run: sh Action/test.sh

set -eu

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

mkdir "$work/bin"
cat >"$work/bin/simwalk" <<'STUB'
#!/bin/sh
# Records one argument per line; exit code and effects come from STUB_* variables.
{ for a in "$@"; do printf '%s\n' "$a"; done; echo --; } >>"$STUB_LOG"
case "$1 $2" in
  "lease acquire") printf 'udid: UDID-1\ntoken: TOKEN-1\n'; exit 0 ;;
  "lease release") exit 0 ;;
esac
case "$1" in
  walk)
    shift
    while [ $# -gt 0 ]; do
      [ "$1" = --output ] && mkdir -p "$2"
      shift
    done
    echo "walk answer"
    exit "${STUB_WALK_CODE:-0}"
    ;;
  bundle)
    echo "$2 answer"
    if [ "$2" = diff ]; then exit "${STUB_DIFF_CODE:-0}"; fi
    exit "${STUB_AUDIT_CODE:-0}"
    ;;
esac
exit 0
STUB
cat >"$work/bin/gh" <<'STUB'
#!/bin/sh
# Records the call; answers the endpoints the scripts use. A --jq filter is applied with real jq to
# the canned JSON, so the scripts' own filters run.
{ for a in "$@"; do printf '%s\n' "$a"; done; echo --; } >>"$STUB_LOG"
filter=.
prev=
for a in "$@"; do
  if [ "$prev" = --jq ]; then filter=$a; fi
  prev=$a
done
case "$*" in
  "api user"*)
    if [ -n "${STUB_USER_FAIL:-}" ]; then exit 1; fi
    printf '{"login":"%s"}' "${STUB_LOGIN:-me}" | jq -r "$filter"
    ;;
  *"/actions/artifacts?name="*) cat "$STUB_ARTIFACTS" ;;
  *"/zip"*) cat "$STUB_ZIP" ;;
  *"/issues/"*"/comments"*"--paginate"*) printf '%s' "${STUB_COMMENTS:-[]}" | jq -r "$filter" ;;
esac
exit 0
STUB
cat >"$work/bin/brew" <<'STUB'
#!/bin/sh
echo "$*" >>"$STUB_LOG"
STUB
chmod +x "$work/bin/"*
PATH="$work/bin:$PATH"
export PATH
STUB_LOG="$work/log"
export STUB_LOG

passed=0
failed=0
ok() { passed=$((passed + 1)); }
bad() {
  failed=$((failed + 1))
  echo "FAIL: $1"
}
expect() { # name, expected, actual
  if [ "$2" = "$3" ]; then ok; else
    bad "$1: expected '$2', got '$3'"
  fi
}
fresh() { # a clean output directory and log
  rm -rf "$work/out"
  mkdir "$work/out"
  : >"$STUB_LOG"
  SIMWALK_OUT="$work/out"
  export SIMWALK_OUT
}
code_of() { # runs the rest, prints its exit code
  set +e
  "$@" >"$work/stdout" 2>&1
  _c=$?
  set -e
  echo "$_c"
}

# --- verdict: the fail-on mapping -------------------------------------------------------------
verdict_case() { # fail-on, walk code, diff code, expected exit
  fresh
  printf 'walk=%s\ndiff=%s\naudit=0\n' "$2" "$3" >"$work/out/codes"
  expect "verdict fail-on=$1 walk=$2 diff=$3" "$4" "$(SIMWALK_FAIL_ON=$1 code_of sh "$here/verdict.sh")"
}
verdict_case qualified 0 0 0
verdict_case qualified 1 0 1
verdict_case qualified 0 2 1
verdict_case qualified 0 7 1
verdict_case refused 0 0 0
verdict_case refused 1 0 1
verdict_case refused 0 2 0
verdict_case refused 2 2 0
verdict_case refused 0 7 1
verdict_case refused 0 64 1
fresh
: >"$work/out/codes"
expect "verdict with nothing recorded fails" 1 "$(SIMWALK_FAIL_ON=refused code_of sh "$here/verdict.sh")"
fresh
echo walk=0 >"$work/out/codes"
expect "verdict refuses an unknown fail-on" 1 "$(SIMWALK_FAIL_ON=nonsense code_of sh "$here/verdict.sh")"

# --- walk: arguments, the reference decides the diff, codes recorded --------------------------
fresh
SIMWALK_WALKBOOK="$work/my book.json" SIMWALK_APP_PATH="" SIMWALK_LEASE_TOKEN=TOKEN-1 sh "$here/walk.sh" >/dev/null
expect "walk without a reference records walk and audit only" "walk=0
audit=0" "$(cat "$work/out/codes")"
if grep -q '^diff$' "$STUB_LOG"; then bad "walk diffed with no reference"; else ok; fi
if grep -qx -- '--app-path' "$STUB_LOG"; then bad "walk passed --app-path with none given"; else ok; fi

fresh
mkdir "$work/out/reference.simwalk"
SIMWALK_WALKBOOK=w.json SIMWALK_APP_PATH=App.app SIMWALK_LEASE_TOKEN=TOKEN-1 STUB_DIFF_CODE=2 STUB_AUDIT_CODE=1 sh "$here/walk.sh" >/dev/null
expect "walk records each code" "walk=0
diff=2
audit=1" "$(cat "$work/out/codes")"
diff_args=$(awk '/^bundle$/{getline; if ($0=="diff"){getline a; getline b; getline c; print a "|" b "|" c}}' "$STUB_LOG" | sed "s|$work/out/||g")
expect "diff takes the reference first, then the run, then --crops" "reference.simwalk|run.simwalk|--crops" "$diff_args"
if grep -qx 'App.app' "$STUB_LOG"; then ok; else bad "walk did not pass --app-path"; fi

fresh
SIMWALK_WALKBOOK=w.json SIMWALK_LEASE_TOKEN=T STUB_WALK_CODE=1 sh "$here/walk.sh" >/dev/null
expect "a refused walk with a bundle still records its code" "walk=1
audit=0" "$(cat "$work/out/codes")"

fresh
for code in 0 2 1; do
  : >"$work/gh-out2"
  SIMWALK_WALKBOOK=w.json SIMWALK_LEASE_TOKEN=T STUB_WALK_CODE=$code GITHUB_OUTPUT="$work/gh-out2" sh "$here/walk.sh" >/dev/null
  if [ "$code" = 1 ]; then
    expect "a refused walk's partial bundle is not a reference" "" "$(cat "$work/gh-out2")"
  else
    expect "walk code $code writes bundle=true" "bundle=true" "$(cat "$work/gh-out2")"
  fi
done

# --- inert inputs -----------------------------------------------------------------------------
fresh
marker="$work/pwned"
hostile="a b \$(touch $marker) \`touch $marker\`; touch $marker"
SIMWALK_WALKBOOK="$hostile.json" SIMWALK_APP_PATH="$hostile.app" SIMWALK_LEASE_TOKEN=T sh "$here/walk.sh" >/dev/null
if [ -e "$marker" ]; then bad "walk executed an input"; else ok; fi
if grep -qxF -- "$hostile.json" "$STUB_LOG" && grep -qxF -- "$hostile.app" "$STUB_LOG"; then ok; else bad "walk altered an input with spaces or \$(...)"; fi

fresh
SIMWALK_DEVICE="$hostile" HOME="$work" GITHUB_OUTPUT="$work/gh-out" sh "$here/install.sh" >"$work/install-out"
if [ -e "$marker" ]; then bad "install executed the device input"; else ok; fi
if grep -qxF -- "$hostile" "$STUB_LOG"; then ok; else bad "install altered the device input"; fi
expect "install reports udid and token" "udid=UDID-1
token=TOKEN-1" "$(cat "$work/gh-out")"

mask_line=$(grep -n '^::add-mask::TOKEN-1$' "$work/install-out" | head -n 1 | cut -d: -f1)
token_line=$(grep -n 'token: TOKEN-1' "$work/install-out" | head -n 1 | cut -d: -f1)
if [ -n "$mask_line" ] && [ -n "$token_line" ] && [ "$mask_line" -lt "$token_line" ]; then ok; else bad "the token was printed before it was masked ($mask_line, $token_line)"; fi

# --- reference lookup -------------------------------------------------------------------------
cat >"$work/artifacts.json" <<'JSON'
{"artifacts":[
 {"id":11,"expired":false,"created_at":"2026-10-01T00:00:00Z","workflow_run":{"head_branch":"main","head_repository_id":1,"repository_id":1}},
 {"id":12,"expired":false,"created_at":"2026-10-03T00:00:00Z","workflow_run":{"head_branch":"feature","head_repository_id":1,"repository_id":1}},
 {"id":13,"expired":true,"created_at":"2026-10-04T00:00:00Z","workflow_run":{"head_branch":"main","head_repository_id":1,"repository_id":1}},
 {"id":14,"expired":false,"created_at":"2026-10-02T00:00:00Z","workflow_run":{"head_branch":"main","head_repository_id":1,"repository_id":1}},
 {"id":15,"expired":false,"created_at":"2026-10-05T00:00:00Z","workflow_run":{"head_branch":"main","head_repository_id":99,"repository_id":1}}
]}
JSON
(cd "$work" && mkdir zipsrc && echo x >zipsrc/manifest.json && cd zipsrc && zip -q ../ref.zip manifest.json)
STUB_ARTIFACTS="$work/artifacts.json"
STUB_ZIP="$work/ref.zip"
export STUB_ARTIFACTS STUB_ZIP

fresh
GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=main GITHUB_REPOSITORY=o/r sh "$here/reference.sh" >/dev/null
if grep -qx 'repos/o/r/actions/artifacts/14/zip' "$STUB_LOG" && [ -f "$work/out/reference.simwalk/manifest.json" ] && [ ! -f "$work/out/no-reference" ]; then ok; else bad "reference did not pick the newest unexpired artifact of the base"; fi

fresh
GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=release GITHUB_REPOSITORY=o/r SIMWALK_DEFAULT_BRANCH=main sh "$here/reference.sh" >/dev/null
expect "no reference on the base says so" "no reference on release yet; references come from runs on main" "$(cat "$work/out/no-reference")"
if [ -d "$work/out/reference.simwalk" ]; then bad "a reference directory exists with no reference"; else ok; fi

# a fork's run (artifact 15, newest) is not chosen; a failed unzip leaves no directory; the name is URL-encoded
fresh
GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=main GITHUB_REPOSITORY=o/r SIMWALK_REFERENCE_ARTIFACT="my ref" sh "$here/reference.sh" >/dev/null
if grep -qx 'repos/o/r/actions/artifacts/15/zip' "$STUB_LOG"; then bad "a fork's artifact was chosen"; else ok; fi
if grep -qx 'repos/o/r/actions/artifacts?name=my%20ref&per_page=100' "$STUB_LOG"; then ok; else bad "the artifact name was not URL-encoded"; fi

fresh
echo "not a zip" >"$work/bad.zip"
STUB_ZIP="$work/bad.zip" GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=main GITHUB_REPOSITORY=o/r sh "$here/reference.sh" >/dev/null 2>&1
if [ -d "$work/out/reference.simwalk" ] || [ ! -f "$work/out/no-reference" ]; then bad "a failed unzip left a reference directory or no note"; else ok; fi

fresh
GITHUB_EVENT_NAME=push GITHUB_REPOSITORY=o/r sh "$here/reference.sh" >/dev/null
if [ -e "$work/out/no-reference" ] || [ -d "$work/out/reference.simwalk" ]; then bad "reference ran off a pull request"; else ok; fi

# --- comment: create versus update, marker, truncation, pull requests only ---------------------
comment_env() { GITHUB_EVENT_NAME=pull_request GITHUB_REPOSITORY=o/r SIMWALK_PR_NUMBER=5 "$@"; }
fresh
echo "walk answer" >"$work/out/walk.txt"
echo "audit answer" >"$work/out/audit.txt"
echo "no reference on main yet; references come from runs on main" >"$work/out/no-reference"
comment_env sh "$here/comment.sh" >/dev/null
if grep -qx 'POST' "$STUB_LOG" && ! grep -qx 'PATCH' "$STUB_LOG"; then ok; else bad "no existing comment should be created"; fi
if head -n 1 "$work/out/comment.md" | grep -qxF '<!-- simwalk-action -->'; then ok; else bad "comment lacks the marker on line 1"; fi
if grep -q 'Not compared: no reference on main yet' "$work/out/comment.md" && grep -q 'not a pass' "$work/out/comment.md"; then ok; else bad "comment does not state the missing reference"; fi

fresh
echo "walk answer" >"$work/out/walk.txt"
STUB_COMMENTS='[{"id":4242,"user":{"login":"me"},"body":"<!-- simwalk-action -->\nold"}]' comment_env sh "$here/comment.sh" >/dev/null
if grep -qx 'PATCH' "$STUB_LOG" && grep -qx 'repos/o/r/issues/comments/4242' "$STUB_LOG" && ! grep -qx 'POST' "$STUB_LOG"; then ok; else bad "an existing marked comment should be updated in place"; fi

# a human's comment carrying the marker, or one with the marker not first, is not ours
fresh
echo "walk answer" >"$work/out/walk.txt"
STUB_COMMENTS='[{"id":1,"user":{"login":"someone"},"body":"<!-- simwalk-action -->\nplanted"},{"id":2,"user":{"login":"me"},"body":"quoting <!-- simwalk-action --> mid-body"}]' comment_env sh "$here/comment.sh" >/dev/null
if grep -qx 'POST' "$STUB_LOG" && ! grep -qx 'PATCH' "$STUB_LOG"; then ok; else bad "a comment that is not ours was updated"; fi

# the default workflow token cannot read /user: the identity falls back to the Actions bot
fresh
echo "walk answer" >"$work/out/walk.txt"
STUB_USER_FAIL=1 STUB_COMMENTS='[{"id":7,"user":{"login":"me"},"body":"<!-- simwalk-action -->\nx"},{"id":8,"user":{"login":"github-actions[bot]"},"body":"<!-- simwalk-action -->\nx"}]' comment_env sh "$here/comment.sh" >/dev/null
if grep -qx 'repos/o/r/issues/comments/8' "$STUB_LOG" && ! grep -qx 'repos/o/r/issues/comments/7' "$STUB_LOG"; then ok; else bad "the identity fallback did not pick the Actions bot's comment"; fi

fresh
awk 'BEGIN{for(i=0;i<5000;i++) print "a long line of answer text that goes on and on and on"}' >"$work/out/walk.txt"
comment_env sh "$here/comment.sh" >/dev/null
size=$(wc -c <"$work/out/comment.md" | tr -d ' ')
if [ "$size" -lt 65000 ] && grep -q 'Truncated' "$work/out/comment.md"; then ok; else bad "an over-long comment was not truncated with a note ($size bytes)"; fi

# multibyte answers cut past the limit: no split character, balanced fences, the note outside any fence
fresh
awk 'BEGIN{for(i=0;i<1500;i++) print "answer \342\200\224 caf\303\251 \342\200\224 " i " \342\200\224 and on"}' >"$work/out/walk.txt"
awk 'BEGIN{for(i=0;i<1500;i++) print "audit \342\200\224 line " i}' >"$work/out/audit.txt"
comment_env sh "$here/comment.sh" >/dev/null
if [ -f "$work/out/comment.md" ] && grep -q 'Truncated' "$work/out/comment.md"; then ok; else bad "a multibyte over-long comment was not truncated with a note"; fi
if iconv -f UTF-8 -t UTF-8 <"$work/out/comment.md" >/dev/null 2>&1; then ok; else bad "the truncated comment is not valid UTF-8"; fi
fences=$(grep -cx '````' "$work/out/comment.md" || true)
if [ $((fences % 2)) -eq 0 ]; then ok; else bad "the truncated comment's fences do not balance ($fences)"; fi
if tail -n 1 "$work/out/comment.md" | grep -q '^(Truncated'; then ok; else bad "the truncation note is not the last line"; fi

fresh
GITHUB_EVENT_NAME=push GITHUB_REPOSITORY=o/r SIMWALK_PR_NUMBER=5 sh "$here/comment.sh" >/dev/null
if [ -s "$STUB_LOG" ]; then bad "a push event called gh"; else ok; fi

# --- build: the command runs; no command is a no-op ---------------------------------------------
fresh
SIMWALK_BUILD_COMMAND="" sh "$here/build.sh" >/dev/null
SIMWALK_BUILD_COMMAND="touch '$work/built'" sh "$here/build.sh" >/dev/null
if [ -e "$work/built" ]; then ok; else bad "build-command did not run"; fi

# --- release ----------------------------------------------------------------------------------
fresh
SIMWALK_LEASE_TOKEN=TOKEN-1 sh "$here/release.sh" >/dev/null
if grep -qx 'release' "$STUB_LOG" && grep -qx 'TOKEN-1' "$STUB_LOG"; then ok; else bad "release did not release the token"; fi

if [ "$failed" -ne 0 ]; then
  echo "$failed of $((passed + failed)) cases failed"
  exit 1
fi
echo "all $passed cases passed"
