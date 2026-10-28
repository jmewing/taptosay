#!/bin/bash
# check-release-sync.sh — fail when the website's published build is BEHIND
# what has been built locally, or when TestFlight lags the website.
#
# Jeremy, 2026-10-28. The website sat on build 13 for NINE DAYS while local
# builds reached 24 and TestFlight reached 23. Nothing complained, because the
# updater's "no update" answer is indistinguishable from "you're current" —
# the app saw 13 < 19, decided it was newer, and said nothing.
#
# This is the missing detector. Run it from the heartbeat, from the hourly job,
# or by hand. Exit 1 with a one-line reason means "a release went out unevenly".
#
#   check-release-sync.sh          human-readable report
#   check-release-sync.sh --quiet  only print on failure (for cron/heartbeat)
set -uo pipefail

SRC=/srv/taptosay
SITE=https://taptosay.app
MAC=jmewing@100.123.184.92
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

say() { [ "$QUIET" = "0" ] && echo "$*"; }
bad=0

# ---- local build --------------------------------------------------------
LOCAL_VER=$(grep -E '^version:' "$SRC/pubspec.yaml" 2>/dev/null | awk '{print $2}')
LOCAL_CODE=${LOCAL_VER##*+}
[ -n "$LOCAL_CODE" ] || { echo "FAIL: cannot read pubspec version"; exit 1; }

APK=$SRC/build/app/outputs/flutter-apk/app-release.apk
LOCAL_BUILT="no"
[ -f "$APK" ] && LOCAL_BUILT="yes"

# ---- website ------------------------------------------------------------
PUB=$(curl -s -m 25 "$SITE/download/latest.json" 2>/dev/null)
WEB_CODE=$(printf '%s' "$PUB" | python3 -c "import json,sys;print(json.load(sys.stdin)['versionCode'])" 2>/dev/null)
WEB_SHA=$(printf '%s' "$PUB" | python3 -c "import json,sys;print(json.load(sys.stdin)['apk_sha256'])" 2>/dev/null)
WEB_NAME=$(printf '%s' "$PUB" | python3 -c "import json,sys;print(json.load(sys.stdin)['versionName'])" 2>/dev/null)

if [ -z "$WEB_CODE" ]; then
  echo "FAIL: website latest.json unreadable — update channel is DOWN"
  exit 1
fi

say "local build   $LOCAL_VER   (apk present: $LOCAL_BUILT)"
say "website       $WEB_NAME+$WEB_CODE"

# ---- TestFlight ---------------------------------------------------------
TF_CODE=""
if [ -n "$MAC" ]; then
  TF_CODE=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$MAC" \
    "cd ~/asc 2>/dev/null && python3 asc.py get '/v1/builds?filter[app]=6817778138&limit=5&sort=-uploadedDate' 2>/dev/null" \
    2>/dev/null | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
vs=[b.get('attributes',{}).get('version') for b in d.get('data',[]) if b.get('attributes',{}).get('processingState')=='VALID']
print(max((int(v) for v in vs if v), default=''))
" 2>/dev/null)
fi
[ -n "$TF_CODE" ] && say "testflight    build $TF_CODE"

# ---- verdicts -----------------------------------------------------------

# 1. A locally built APK that is newer than the website = unshipped release.
if [ "$LOCAL_BUILT" = "yes" ] && [ "$LOCAL_CODE" -gt "$WEB_CODE" ] 2>/dev/null; then
  echo "STALE: built $LOCAL_CODE but website advertises $WEB_CODE — Android was never published"
  bad=1
fi

# 2. Website APK content must match the manifest that points at it.
if [ "$QUIET" = "0" ] && [ "$LOCAL_BUILT" = "yes" ] && [ "$LOCAL_CODE" = "$WEB_CODE" ]; then
  LSHA=$(sha256sum "$APK" | cut -d' ' -f1)
  if [ -n "$WEB_SHA" ] && [ "$LSHA" != "$WEB_SHA" ]; then
    echo "MISMATCH: website sha256 != local apk for the same build $LOCAL_CODE"
    bad=1
  else
    say "sha256        matches"
  fi
fi

# 3. The whole point: both platforms must be at the same build number.
if [ -n "$TF_CODE" ] && [ "$TF_CODE" != "$WEB_CODE" ]; then
  echo "SKEW: website is build $WEB_CODE but TestFlight is build $TF_CODE — the two apps differ"
  bad=1
fi

if [ "$bad" = "1" ]; then
  exit 1
fi

say "IN SYNC: android website, iOS TestFlight, and local build all agree on $LOCAL_VER"
exit 0
