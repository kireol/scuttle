#!/usr/bin/env bash
# Add a Frigate server to Scuttle via the app's ECP input API — no on-screen
# keyboard driving (the old keypress approach broke across Roku OS layouts).
# The app just needs to be RUNNING on the Roku (any screen).
# Usage: scripts/add-server.sh [name] [baseUrl] [username] [password] [rokuIp]
set -euo pipefail
cd "$(dirname "$0")/.."
source .env

NAME="${1:-Home}"
BASE_URL="${2:-https://frigate.example.com:8971}"
USERNAME="${3:-${FRIGATE_USERNAME:?set FRIGATE_USERNAME in .env or pass as arg 3}}"
PASSWORD="${4:-${FRIGATE_PASSWORD:?set FRIGATE_PASSWORD in .env or pass as arg 4}}"
TARGET_IP="${5:-$ROKU_IP}"

enc() { python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"; }

curl -s -o /dev/null -d '' "http://$TARGET_IP:8060/input?cmd=addserver&name=$(enc "$NAME")&url=$(enc "$BASE_URL")&username=$(enc "$USERNAME")&password=$(enc "$PASSWORD")&authtype=frigate&go2rtcport=1984"
echo "Sent: $NAME ($BASE_URL) to Scuttle on $TARGET_IP — it appears in Settings immediately"
