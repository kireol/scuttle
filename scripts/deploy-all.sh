#!/usr/bin/env bash
# Deploy the app to every Roku listed in ROKU_IPS (space-separated, in .env);
# falls back to just ROKU_IP. All devices must share ROKU_DEV_PASSWORD.
# Usage: scripts/deploy-all.sh
set -uo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] || { echo "Missing .env (copy .env.example)"; exit 1; }
source .env

IPS="${ROKU_IPS:-$ROKU_IP}"
mkdir -p out
rm -f out/app.zip
zip -rq out/app.zip manifest source components images

FAIL=0
for ip in $IPS; do
    if ! ping -c 1 -t 2 "$ip" >/dev/null 2>&1; then
        echo "$ip: unreachable — skipped"
        FAIL=1
        continue
    fi
    curl -s -o /dev/null -d '' "http://$ip:8060/keypress/Home" || true
    sleep 1
    RESULT=$(curl -s --user "rokudev:$ROKU_DEV_PASSWORD" --digest \
        -F "mysubmit=Install" -F "archive=@out/app.zip" \
        "http://$ip/plugin_install" || true)
    if echo "$RESULT" | grep -qE "Install Success|Identical to previous version"; then
        # "Identical" installs do not auto-relaunch, and we pressed Home first —
        # always launch so the TV isn't left on the Roku home screen
        sleep 2
        curl -s -o /dev/null -d '' "http://$ip:8060/launch/dev" || true
        echo "$ip: install OK"
    else
        echo "$ip: install FAILED (dev mode off, or wrong password?)"
        FAIL=1
    fi
done
exit $FAIL
