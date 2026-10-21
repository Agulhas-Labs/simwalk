#!/bin/sh
#
# Posts the answers as one pull request comment, found by a hidden marker and updated in place, else
# created. Only on pull_request events. Inputs: SIMWALK_OUT, GITHUB_REPOSITORY, GITHUB_EVENT_NAME,
# SIMWALK_PR_NUMBER, GH_TOKEN (read by gh).

set -eu

if [ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]; then
  echo "not a pull request; no comment"
  exit 0
fi

out=${SIMWALK_OUT:?}
repo=${GITHUB_REPOSITORY:?}
pr=${SIMWALK_PR_NUMBER:?}
marker='<!-- simwalk-action -->'
limit=60000 # GitHub refuses a comment over 65536 characters

section() { # heading, file
  printf '### %s\n\n````\n' "$1"
  if [ -f "$2" ]; then cat "$2"; else echo "(no answer)"; fi
  printf '\n````\n\n'
}

mkdir -p "$out"
body="$out/comment.md"
{
  printf '%s\n## SimWalk\n\n' "$marker"
  section "Walk" "$out/walk.txt"
  if [ -f "$out/no-reference" ]; then
    printf '### Diff\n\nNot compared: %s. This is not a pass.\n\n' "$(cat "$out/no-reference")"
  elif [ -f "$out/diff.txt" ]; then
    section "Diff against the base branch" "$out/diff.txt"
  fi
  if [ -f "$out/audit.txt" ]; then section "Audit" "$out/audit.txt"; fi
} >"$body.full"

size=$(wc -c <"$body.full" | tr -d ' ')
if [ "$size" -gt "$limit" ]; then
  # Cut at a line boundary: drop the (possibly partial) last line of the first $limit bytes, so no
  # multibyte character is split; close a fence the cut left open, then add the note outside it.
  head -c "$limit" "$body.full" | sed '$d' >"$body"
  fences=$(grep -cx '````' "$body" || true)
  if [ $((fences % 2)) -eq 1 ]; then printf '````\n' >>"$body"; fi
  printf '\n\n(Truncated: the answers were %s bytes and a comment holds %s. The full text is in the uploaded bundle artifact.)\n' "$size" "$limit" >>"$body"
else
  cp "$body.full" "$body"
fi
rm -f "$body.full"

# Only our own comment counts: the marker starts the body and the author is this token's identity. The
# default workflow token cannot read /user, so its identity is the Actions bot.
login=$(gh api user --jq .login 2>/dev/null) || login=''
if [ -z "$login" ]; then login='github-actions[bot]'; fi
id=$(gh api "repos/$repo/issues/$pr/comments" --paginate \
  --jq ".[] | select((.body | startswith(\"$marker\")) and .user.login == \"$login\") | .id" | head -n 1)

if [ -n "$id" ]; then
  gh api --method PATCH "repos/$repo/issues/comments/$id" -F "body=@$body" >/dev/null
  echo "updated comment $id"
else
  gh api --method POST "repos/$repo/issues/$pr/comments" -F "body=@$body" >/dev/null
  echo "created a comment"
fi
