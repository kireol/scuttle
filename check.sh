#!/usr/bin/env bash
# Off-device validation: compiles the project with BrighterScript (bsc).
# Used in place of on-device runs while no Roku is available.
set -uo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/opt/node-v20.19.0-linux-x64/bin:$PATH"
./node_modules/.bin/bsc --project bsconfig.json
rc=$?
if [[ $rc -eq 0 ]]; then echo "CHECK OK"; else echo "CHECK FAILED"; fi
exit $rc
