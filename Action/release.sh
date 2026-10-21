#!/bin/sh
#
# Gives the lease back. Runs in an always() step, so it never fails the job. Input: SIMWALK_LEASE_TOKEN.

set -u

if [ -z "${SIMWALK_LEASE_TOKEN:-}" ]; then
  echo "no lease was taken; nothing to release"
  exit 0
fi
simwalk lease release "$SIMWALK_LEASE_TOKEN" || echo "::warning::could not release the lease"
exit 0
