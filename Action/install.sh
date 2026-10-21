#!/bin/sh
#
# Installs SimWalk from the Homebrew tap and leases a simulator for this job.
# Writes `udid` and `token` to $GITHUB_OUTPUT. Input: SIMWALK_DEVICE (optional simulator name).

set -eu

brew install agulhas-labs/tap/simwalk

# A lease lives as long as its holder or its ttl; a job's steps are separate shells, so ask for the
# longest ttl a job needs and release it in the always() step.
if [ -n "${SIMWALK_DEVICE:-}" ]; then
  answer=$(simwalk lease acquire --device "$SIMWALK_DEVICE" --ttl 2h)
else
  answer=$(simwalk lease acquire --ttl 2h)
fi
udid=$(printf '%s\n' "$answer" | sed -n 's/^udid: *//p' | head -n 1)
token=$(printf '%s\n' "$answer" | sed -n 's/^token: *//p' | head -n 1)
# Mask before anything prints the answer: it carries the token.
if [ -n "$token" ]; then echo "::add-mask::$token"; fi
printf '%s\n' "$answer"
if [ -z "$udid" ] || [ -z "$token" ]; then
  echo "::error::simwalk lease acquire did not print a udid and a token"
  exit 1
fi

{
  echo "udid=$udid"
  echo "token=$token"
} >>"${GITHUB_OUTPUT:?}"
