#!/usr/bin/env bash
# Dev helper: hand-drive one View so the menubar's "Watched today" number moves.
# Stands in for the extension's capture side, which lands in a later slice.
#
# Posts a real Flush every 5s for one View — mediaFound, play, a `sample`
# heartbeat per tick, then `viewEnded` — exactly the cadence the extension will
# use. Watch "Watched today · Ns" climb in the menubar.
#
# Usage:  ./scripts/fake-session.sh [watch-seconds] [port] [--background]
#   defaults: 30 seconds, port 48920, foreground (counts as Watched time)
#   --background sends `hidden` first, so the time accrues as Background audio
#                and "Watched today" stays put.
#
# Run `swift run WatchLogs` in another terminal first.

set -euo pipefail

WATCH_SECONDS="${1:-30}"
PORT="${2:-48920}"
BACKGROUND="false"
[[ "${3:-}" == "--background" ]] && BACKGROUND="true"

# WATCHLOGS_TOKEN overrides the Keychain lookup — handy against a test server.
TOKEN="${WATCHLOGS_TOKEN:-$(security find-generic-password -s com.watchlogs.app -a loopback-token -w)}"
if [[ -z "${TOKEN}" ]]; then
  echo "no token in the Keychain — start the app once (swift run WatchLogs) so it mints one" >&2
  exit 1
fi

VIEW_ID="view-$(uuidgen)"
SEQ=1
PENDING=()

now_ms() { echo $(( $(date +%s) * 1000 )); }

push() {
  PENDING+=("$1")
  SEQ=$((SEQ + 1))
}

# POST everything buffered since the last Ack. $1 is the View's `open` flag.
flush() {
  local open="$1"
  local events
  events="$(IFS=,; echo "${PENDING[*]}")"
  local body
  body=$(cat <<JSON
{"schemaVersion":1,"flushId":"$(uuidgen)","sentAt":$(now_ms),
 "agent":{"extInstanceId":"fake-session","extVersion":"0.1.0","browser":"chrome","os":"macOS"},
 "views":[{"viewId":"${VIEW_ID}","service":"youtube","contentFormat":"standard","embedded":false,
   "videoId":"dQw4w9WgXcQ","url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ",
   "title":"Never Gonna Give You Up","author":"Rick Astley","durationSec":213,
   "metadataSource":"adapter","adapterId":"youtube","tabId":41,"startedAt":${STARTED_AT},
   "open":${open},"previousViewId":null,"events":[${events}]}]}
JSON
)
  printf '%s  ' "$(date +%H:%M:%S)"
  local ack
  ack="$(curl -sS -X POST "http://127.0.0.1:${PORT}/v1/flush" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "${body}")"
  echo "ack ${ack}"
  # The extension prunes every Event at or below ackSeq; so do we.
  PENDING=()
}

STARTED_AT="$(now_ms)"
echo "view ${VIEW_ID} — ${WATCH_SECONDS}s, background=${BACKGROUND}"

push "{\"seq\":${SEQ},\"type\":\"mediaFound\",\"t\":$(now_ms),\"pos\":0}"
if [[ "${BACKGROUND}" == "true" ]]; then
  push "{\"seq\":${SEQ},\"type\":\"hidden\",\"t\":$(now_ms),\"pos\":0}"
fi
push "{\"seq\":${SEQ},\"type\":\"play\",\"t\":$(now_ms),\"pos\":0}"
flush true

VISIBLE="true"
[[ "${BACKGROUND}" == "true" ]] && VISIBLE="false"

elapsed=0
while (( elapsed < WATCH_SECONDS )); do
  step=5
  (( elapsed + step > WATCH_SECONDS )) && step=$((WATCH_SECONDS - elapsed))
  sleep "${step}"
  elapsed=$((elapsed + step))
  push "{\"seq\":${SEQ},\"type\":\"sample\",\"t\":$(now_ms),\"pos\":${elapsed},\"playing\":true,\"visible\":${VISIBLE}}"
  flush true
done

push "{\"seq\":${SEQ},\"type\":\"viewEnded\",\"t\":$(now_ms),\"pos\":${elapsed},\"reason\":\"nav\"}"
flush false
echo "done — the menubar should show ${WATCH_SECONDS}s more of $( [[ ${BACKGROUND} == true ]] && echo 'Background audio' || echo 'Watched time' )"
