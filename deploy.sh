#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
[[ -f .env ]] || { echo "Missing .env (copy .env.example)"; exit 1; }
source .env

mkdir -p out
rm -f out/app.zip
zip -rq out/app.zip manifest source components images

# Exit any running channel so install always succeeds
curl -s -o /dev/null -d '' "http://$ROKU_IP:8060/keypress/Home"
sleep 1

RESULT=$(curl -s --user "rokudev:$ROKU_DEV_PASSWORD" --digest \
    -F "mysubmit=Install" -F "archive=@out/app.zip" \
    "http://$ROKU_IP/plugin_install")
if echo "$RESULT" | grep -qE "Install Success|Identical to previous version"; then
    echo "Install OK"
else
    echo "Install FAILED"; echo "$RESULT" | grep -oE "<font[^>]*>[^<]*" | head -5
    exit 1
fi

if [[ "${1:-}" == "--test" ]]; then
    LOG=out/test.log
    : > "$LOG"
    # Instant-Resume devices only RESUME on ECP launch (args ignored), so a
    # cold start with RunTests=true cannot be guaranteed. Instead make sure the
    # app is running, then trigger the suite via the ECP input API, which the
    # main event loop handles in any state.
    # Connect console BEFORE triggering so no output is missed.
    # No `timeout` (absent on macOS); the poll loop below bounds the wait and kills nc.
    # </dev/null so backgrounded nc never reads the terminal (SIGTTIN would suspend it).
    nc "$ROKU_IP" 8085 > "$LOG" 2>/dev/null </dev/null &
    NC_PID=$!
    curl -s -o /dev/null -d '' "http://$ROKU_IP:8060/launch/dev" || true
    # The input command is lost if it lands while the app is still compiling
    # after install, so retry until the suite acknowledges it started.
    for _ in 1 2 3; do
        sleep 8
        curl -s -o /dev/null -d '' "http://$ROKU_IP:8060/input?cmd=runtests"
        sleep 2
        grep -q "\[TESTS START\]" "$LOG" && break
    done
    for _ in $(seq 1 35); do
        grep -q "\[TESTS DONE\]\|\[TESTS FAILED\]" "$LOG" && break
        sleep 1
    done
    kill "$NC_PID" 2>/dev/null || true
    sed -n '/\[TESTS START\]/,/\[TESTS DONE\]\|\[TESTS FAILED\]/p' "$LOG"
    grep -q "\[TESTS DONE\]" "$LOG" && exit 0
    echo "TESTS FAILED (or no output)"; exit 1
fi
