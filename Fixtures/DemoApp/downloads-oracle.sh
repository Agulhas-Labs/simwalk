#!/bin/sh
# The value oracle for the demo app's Usage screen (downloads.walkbook.json). Needs macOS's `date` (BSD `-j -f`).
#
# Reads one JSON request per line on stdin (keys sorted: capturedAt, figure, locale, screen, state, windows) and writes
# exactly one JSON reply per request line, in order. It answers from DemoApp/downloads.csv (found from this script's own
# path, not the cwd) as of the request's capturedAt, with the same inclusion rules as the app:
#   today   downloads since local midnight (honours TZ): capturedAt - 60*minutes_ago >= midnight
#   last24h downloads under 1440 minutes old
# Figures: downloads-today → count; data-today → megabyte sum (%.1f, MB); average-download → sum/count (%.4f, MB).
# Windows are answered as asked, in the order asked. An unknown figure or window, or an empty window for the
# average, is an {"error":…} for that request alone.
csv="$(dirname "$0")/DemoApp/downloads.csv"
# awk reads and prints numbers in the locale's form, so under a comma-decimal locale 38.2 would read as 38 and a reply
# would print 1272,6, which is not JSON. The protocol's numbers are JSON's, whatever the user's region.
export LC_ALL=C

while IFS= read -r line || [ -n "$line" ]; do
  at=$(printf '%s' "$line" | sed -n 's/.*"capturedAt":"\([^"]*\)".*/\1/p')
  figure=$(printf '%s' "$line" | sed -n 's/.*"figure":"\([^"]*\)".*/\1/p' | tr -d '\\')
  windows=$(printf '%s' "$line" | sed -n 's/.*"windows":\[\([^]]*\)\].*/\1/p' | tr -d '"\\' | tr ',' ' ')
  case "$figure" in
    downloads-today | data-today | average-download) ;;
    *) printf '{"error":"no figure named %s; this oracle knows downloads-today, data-today, average-download"}\n' "$figure"; continue ;;
  esac
  stamp=$(printf '%s' "$at" | sed 's/\.[0-9]*Z$//; s/Z$//')
  epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$stamp" +%s 2>/dev/null)
  if [ -z "$epoch" ]; then printf '{"error":"unreadable capturedAt"}\n'; continue; fi
  midnight=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date -r "$epoch" +%Y-%m-%d) 00:00:00" +%s)
  bad=""
  for w in $windows; do
    case "$w" in today | last24h) ;; *) bad="$w"; break ;; esac
  done
  if [ -n "$bad" ]; then printf '{"error":"no window named %s; this oracle knows today and last24h"}\n' "$bad"; continue; fi
  # one awk pass per request: emits the JSON reply (or an error) for the requested windows
  printf '%s\n' "$windows" | awk -v epoch="$epoch" -v midnight="$midnight" -v figure="$figure" -v at="$at" -v csv="$csv" '
    { nw = split($0, ws, " ") }
    END {
      nt = 0; st = 0; n24 = 0; s24 = 0
      while ((getline row < csv) > 0) {
        split(row, f, ",")
        if (f[1] !~ /^[0-9]+$/) continue
        if (epoch - 60 * f[1] >= midnight) { nt++; st += f[2] }
        if (f[1] < 1440) { n24++; s24 += f[2] }
      }
      out = ""
      for (i = 1; i <= nw; i++) {
        w = ws[i]
        n = (w == "today") ? nt : n24
        s = (w == "today") ? st : s24
        if (figure == "downloads-today") v = sprintf("%d", n)
        else if (figure == "data-today") v = sprintf("%.1f", s)
        else {
          if (n == 0) { printf "{\"error\":\"no downloads in window %s\"}\n", w; exit }
          v = sprintf("%.4f", s / n)
        }
        out = out (i > 1 ? "," : "") "\"" w "\":" v
      }
      unit = (figure == "downloads-today") ? "downloads" : "MB"
      att = ""
      for (i = 1; i <= nw; i++) att = att (i > 1 ? ", " : "") ((ws[i] == "today") ? nt : n24) " in " ws[i]
      printf "{\"values\":{%s},\"unit\":\"%s\",\"attribution\":\"downloads.csv as of %s: %s\"}\n", out, unit, at, att
    }'
done
