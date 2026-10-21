#!/bin/sh
#
# Sets the check from the exit codes walk.sh recorded. ok is 0, refused 1, qualified 2.
# fail-on qualified fails on 1 and 2; refused fails on 1 only; any other code always fails.
# Inputs: SIMWALK_OUT, SIMWALK_FAIL_ON.

set -eu

out=${SIMWALK_OUT:?}
fail_on=${SIMWALK_FAIL_ON:-qualified}

case "$fail_on" in
  qualified | refused) ;;
  *)
    echo "::error::fail-on is '$fail_on'; it must be qualified or refused"
    exit 1
    ;;
esac

failed=0
while IFS='=' read -r step code; do
  [ -n "$step" ] || continue
  case "$code" in
    0) ;;
    1)
      echo "::error::$step was refused (exit 1)"
      failed=1
      ;;
    2)
      if [ "$fail_on" = qualified ]; then
        echo "::error::$step was qualified (exit 2)"
        failed=1
      else
        echo "::warning::$step was qualified (exit 2); fail-on is refused"
      fi
      ;;
    *)
      echo "::error::$step exited $code"
      failed=1
      ;;
  esac
done <"$out/codes"

if [ ! -s "$out/codes" ]; then
  echo "::error::no walk was recorded"
  failed=1
fi
exit "$failed"
