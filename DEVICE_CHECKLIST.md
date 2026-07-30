# Device Verification Checklist

## Task 1

The following on-device verification steps were skipped (no Roku device available):
- Deploy via `./deploy.sh`
- TV shows the skeleton text "Frigate for Roku — skeleton OK"

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)

## Task 2

The following on-device verification steps were skipped (no Roku device available):
- Run: `./deploy.sh --test`
- Expected: PASS: math works, [TESTS DONE], exit 0

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)

## Task 3

The following on-device verification steps were skipped (no Roku device available):
- Run: `./deploy.sh --test`
- Expected: all Test_ServerStore asserts PASS, [TESTS DONE], exit 0

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)

## Task 4

The following on-device verification steps were skipped (no Roku device available):
- Run: `./deploy.sh --test`
- Expected: all Test_FrigateUrls asserts PASS (including the base64 basic-auth and cookie-parse asserts, which exercise roByteArray/string APIs only a real device fully verifies), [TESTS DONE], exit 0

Validation: BrighterScript compilation checked via `./check.sh` ✓ (CHECK OK)
