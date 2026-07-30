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
    # Connect console BEFORE launching so no output is missed
    ( timeout 40 nc "$ROKU_IP" 8085 > "$LOG" 2>/dev/null || true ) &
    NC_PID=$!
    sleep 1
    curl -s -o /dev/null -d '' "http://$ROKU_IP:8060/launch/dev?RunTests=true"
    for _ in $(seq 1 35); do
        grep -q "\[TESTS DONE\]\|\[TESTS FAILED\]" "$LOG" && break
        sleep 1
    done
    kill "$NC_PID" 2>/dev/null || true
    sed -n '/\[TESTS START\]/,/\[TESTS DONE\]\|\[TESTS FAILED\]/p' "$LOG"
    grep -q "\[TESTS DONE\]" "$LOG" && exit 0
    echo "TESTS FAILED (or no output)"; exit 1
fi
