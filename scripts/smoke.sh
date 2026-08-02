#!/usr/bin/env bash
# On-device smoke test: cold-start the installed dev channel, watch the debug
# console for runtime errors, and save a screenshot of the home screen.
# Assumes the channel is already installed (run ./deploy.sh first).
# Usage: scripts/smoke.sh [wait-seconds]   (default 15)
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] || { echo "Missing .env (copy .env.example)"; exit 1; }
source .env

WAIT="${1:-15}"
LOG=out/smoke.log
SHOT=out/smoke_home.jpg
mkdir -p out
: > "$LOG"

# Cold start: a launch of an already-running app only resumes it
curl -s -o /dev/null -d '' "http://$ROKU_IP:8060/keypress/Home"
sleep 2

# Telnet 8085 replays a backlog and is single-client; capture fresh output
nc "$ROKU_IP" 8085 > "$LOG" 2>/dev/null </dev/null &
NC_PID=$!
sleep 1
curl -s -o /dev/null -d '' "http://$ROKU_IP:8060/launch/dev"
sleep "$WAIT"
kill "$NC_PID" 2>/dev/null || true

# Screenshot via the dev web installer
curl -s --user "rokudev:$ROKU_DEV_PASSWORD" --digest \
    -F "mysubmit=Screenshot" "http://$ROKU_IP/plugin_inspect" -o /dev/null
curl -s --user "rokudev:$ROKU_DEV_PASSWORD" --digest \
    "http://$ROKU_IP/pkgs/dev.jpg" -o "$SHOT"

FAIL=0
if grep -qiE "runtime error|Backtrace:|Syntax Error" "$LOG"; then
    echo "SMOKE FAILED — errors in console:"
    grep -iE -B2 -A8 "runtime error|Backtrace:|Syntax Error" "$LOG" | head -40
    FAIL=1
else
    echo "Console clean after ${WAIT}s."
fi
grep -E "\[home\]|\[live\]|\[main\]" "$LOG" | tail -5 || true
echo "Screenshot: $SHOT"
exit $FAIL
