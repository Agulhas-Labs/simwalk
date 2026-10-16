#!/bin/sh
# A value oracle answering fixed values, for CommandOracle's tests. $1 picks how it behaves:
#   fixed    one reply per request line: steps-today → a real app's values, distance → 4.23 km, anything else → an error
#   exit     reads its input, complains on stderr, exits 3
#   sleep    outlives any bound a test sets
#   grandchild <pidfile>  runs sleep without exec, as a script running python3 would, writing the sleep's pid to <pidfile>
#   stubborn-grandchild <pidfile>  as grandchild, but the sleep ignores SIGTERM and runs as simwalk-oracle-stubborn-grandchild
#   garbage  one line per request that is not JSON
#   short    one reply, however many requests
mode="${1:-fixed}"
case "$mode" in
  exit) cat >/dev/null; echo "store not seeded" >&2; exit 3 ;;
  sleep) sleep 5; exit 0 ;;
  grandchild) /bin/sh -c 'echo $$ > "$0"; exec sleep 30' "$2"; exit 0 ;;
  stubborn-grandchild) /bin/bash -c 'trap "" TERM; echo $$ > "$0"; exec -a simwalk-oracle-stubborn-grandchild sleep 30' "$2"; exit 0 ;;
esac
answered=0
while IFS= read -r line; do
  [ "$mode" = short ] && [ "$answered" -gt 0 ] && continue
  answered=$((answered + 1))
  if [ "$mode" = garbage ]; then echo "steps: lots"; continue; fi
  case "$line" in
    *'"figure":"steps-today"'*) echo '{"values":{"midnight":3326,"rolling24h":2703},"unit":"count","attribution":"stepCount sum over the seeded store"}' ;;
    *'"figure":"distance"'*) echo '{"values":{"midnight":4.23,"rolling24h":3.9},"unit":"km"}' ;;
    *) echo '{"error":"no such figure"}' ;;
  esac
done
