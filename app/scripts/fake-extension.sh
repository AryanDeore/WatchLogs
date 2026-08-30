#!/usr/bin/env bash
# Dev helper: stand in for the extension so you can watch the menubar app go
# "Connected" without loading Chrome. Reads the token from the Keychain and POSTs
# an empty-views heartbeat every few seconds.
#
# Usage:  ./scripts/fake-extension.sh [port] [interval-seconds]
#   defaults: port 48920, interval 3
#
# Run `swift run WatchLogs` in another terminal first.

set -euo pipefail

PORT="${1:-48920}"
INTERVAL="${2:-3}"

TOKEN="$(security find-generic-password -s com.watchlogs.app -a loopback-token -w)"
if [[ -z "${TOKEN}" ]]; then
  echo "no token in the Keychain — start the app once (swift run WatchLogs) so it mints one" >&2
  exit 1
fi

echo "pinging http://127.0.0.1:${PORT}/v1/ping ..."
curl -sS "http://127.0.0.1:${PORT}/v1/ping"; echo

echo "heartbeat every ${INTERVAL}s (Ctrl-C to stop) — the menubar line should read \"Connected · last flush <n>s ago\""
while true; do
  body="{\"schemaVersion\":1,\"flushId\":\"$(uuidgen)\",\"sentAt\":$(($(date +%s) * 1000)),\"agent\":{\"extInstanceId\":\"fake-ext\",\"extVersion\":\"0.1.0\",\"browser\":\"chrome\",\"os\":\"macOS\"},\"views\":[]}"
  printf '%s  ' "$(date +%H:%M:%S)"
  curl -sS -o /dev/null -w 'flush -> %{http_code}\n' \
    -X POST "http://127.0.0.1:${PORT}/v1/flush" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "${body}"
  sleep "${INTERVAL}"
done
