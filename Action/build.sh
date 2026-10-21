#!/bin/sh
#
# Runs the caller's build command, if it gave one. The command is the caller's own shell line and is
# run as such; nothing else the action receives is ever run. Input: SIMWALK_BUILD_COMMAND.

set -eu

if [ -z "${SIMWALK_BUILD_COMMAND:-}" ]; then
  echo "no build-command; walking the app as it is"
  exit 0
fi
sh -c "$SIMWALK_BUILD_COMMAND"
