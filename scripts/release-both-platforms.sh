#!/bin/bash
# release-both-platforms.sh — build AND publish Android + iOS as ONE release.
#
# Jeremy, 2026-10-28, after I published iOS to TestFlight six times while the
# Android website stayed on build 13 for nine days:
#
#   "when it pushes to one it pushes to the other... they both happen at the
#    same fucking time."
#
# Build-then-manually-publish is exactly how that drift happened, so this script
# does the whole thing in one run and REFUSES to report success unless BOTH
# platforms are actually live and verified from the public internet:
#
#   1. build Android APK+AAB and iOS from ONE version (via build-both-platforms.sh,
#      which already proves source parity between the two build hosts)
#   2. publish the APK+AAB to the website and rewrite latest.json
#   3. upload the signed IPA to TestFlight
#   4. verify BOTH from the public internet, and fail loudly if either is stale
#
# Usage:
#   release-both-platforms.sh              # build + publish both
#   release-both-platforms.sh --skip-ios   # Android only (emergency hotfix)
#
# --skip-ios exists because a website security fix may need to ship before an
# App Store review completes. It prints a loud warning and is recorded in the
# release log, so a skipped iOS is never silent.
set -uo pipefail

SRC=/srv/taptosay
MAC=jmewing@100.123.184.92
MACSRC='~/taptosay'
GAZA=jmewing@gaza.tail49ed84.ts.net
APPDIR=/var/www/taptosay.app/download
SITE=https://taptosay.app
LOGDIR=$SRC/build-logs
mkdir -p "$LOGDIR"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
fail() { log "FAIL: $*"; exit 1; }

SKIP_IOS=0
for a in "$@"; do [ "$a" = "--skip-ios" ] && SKIP_IOS=1; done

# ---- 1. build both from one version --------------------------------------
log "=== BUILD BOTH PLATFORMS ==="
bash "$SRC/scripts/build-both-platforms.sh" || fail "dual build failed"
cd "$SRC" || fail "no $SRC"
VER=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
NAME=${VER%%+*}; CODE=${VER##*+}
log "version under release: $VER"

APK=$SRC/build/app/outputs/flutter-apk/app-release.apk
AAB=$SRC/build/app/outputs/bundle/release/app-release.aab
[ -f "$APK" ] || fail "APK missing after build"
[ -f "$AAB" ] || fail "AAB missing after build"

# ---- 2. publish Android to the website -----------------------------------
log "=== PUBLISH ANDROID TO WEBSITE ==="
APK_SHA=$(sha256sum "$APK" | cut -d' ' -f1)
APK_SZ=$(stat -c%s "$APK")

scp -o BatchMode=yes "$APK" "$GAZA:/tmp/taptosay-$NAME-$CODE.apk" >/dev/null 2>&1 \
  || fail "APK upload to gaza failed"
scp -o BatchMode=yes "$AAB" "$GAZA:/tmp/taptosay-$NAME+$CODE.aab" >/dev/null 2>&1 \
  || fail "AAB upload to gaza failed"

ssh -o BatchMode=yes "$GAZA" "bash -s" <<REMOTE || fail "website publish failed on gaza"
set -e
sudo mv /tmp/taptosay-$NAME-$CODE.apk "$APPDIR/taptosay-$NAME-$CODE.apk"
sudo mv /tmp/taptosay-$NAME+$CODE.aab "$APPDIR/taptosay-$NAME+$CODE.aab"
sudo chown www-data:www-data "$APPDIR/taptosay-$NAME-$CODE.apk" "$APPDIR/taptosay-$NAME+$CODE.aab"
sudo chmod 644 "$APPDIR/taptosay-$NAME-$CODE.apk" "$APPDIR/taptosay-$NAME+$CODE.aab"
# repoint the stable symlink, then write the manifest that the app reads
sudo ln -sfn "taptosay-$NAME-$CODE.apk" "$APPDIR/latest.apk"
cat > /tmp/latest.json <<JSON
{
    "versionName": "$NAME",
    "versionCode": $CODE,
    "apk": "https://taptosay.app/download/latest.apk",
    "apk_versioned": "https://taptosay.app/download/taptosay-$NAME-$CODE.apk",
    "apk_sha256": "$APK_SHA",
    "apk_size": $APK_SZ,
    "aab": "https://taptosay.app/download/taptosay-$NAME+$CODE.aab"
}
JSON
sudo mv /tmp/latest.json "$APPDIR/latest.json"
sudo chown www-data:www-data "$APPDIR/latest.json"
sudo chmod 644 "$APPDIR/latest.json"
REMOTE
log "android published: $NAME+$CODE"

# ---- 3. upload iOS to TestFlight ----------------------------------------
if [ "$SKIP_IOS" = "1" ]; then
  log "!!! iOS SKIPPED (--skip-ios) — TestFlight and the website are now OUT OF SYNC"
  log "!!! upload the IPA manually as soon as possible"
else
  log "=== UPLOAD iOS TO TESTFLIGHT ==="
  ssh -o BatchMode=yes "$MAC" "
    export PATH=\$HOME/flutter/bin:/opt/homebrew/bin:\$PATH
    cd $MACSRC || exit 1
    flutter build ipa --release --export-method app-store
  " >"$LOGDIR/ios-ipa-$CODE.log" 2>&1 || fail "iOS IPA build failed (see $LOGDIR/ios-ipa-$CODE.log)"

  KEYID=$(ssh -o BatchMode=yes "$MAC" 'ls ~/.appstoreconnect/private_keys/AuthKey_*.p8 2>/dev/null | head -1 | sed "s/.*AuthKey_//; s/\.p8$//"')
  [ -n "$KEYID" ] || fail "no App Store Connect API key on the Mac"
  ISSUER=2d2f3cf2-0c1f-40b1-bd13-ed669a667c90

  ssh -o BatchMode=yes "$MAC" "
    xcrun altool --upload-app --type ios -f $MACSRC/build/ios/ipa/taptosay.ipa \
      --apiKey $KEYID --apiIssuer $ISSUER
  " >"$LOGDIR/testflight-$CODE.log" 2>&1

  if grep -q "UPLOAD SUCCEEDED" "$LOGDIR/testflight-$CODE.log"; then
    log "testflight upload succeeded"
  else
    grep -iE "error|failed" "$LOGDIR/testflight-$CODE.log" | tail -5
    fail "TestFlight upload failed (see $LOGDIR/testflight-$CODE.log)"
  fi
fi

# ---- 4. verify BOTH from the public internet ----------------------------
log "=== VERIFY PUBLIC STATE ==="
PUB=$(curl -s -m 25 "$SITE/download/latest.json" 2>/dev/null)
PUB_CODE=$(printf '%s' "$PUB" | python3 -c "import json,sys;print(json.load(sys.stdin)['versionCode'])" 2>/dev/null)
[ "$PUB_CODE" = "$CODE" ] || fail "website advertises code '$PUB_CODE', expected '$CODE'"

PUB_SHA=$(printf '%s' "$PUB" | python3 -c "import json,sys;print(json.load(sys.stdin)['apk_sha256'])" 2>/dev/null)
[ "$PUB_SHA" = "$APK_SHA" ] || fail "website apk_sha256 mismatch (site=$PUB_SHA local=$APK_SHA)"
log "website verified: code $PUB_CODE, sha matches"

if [ "$SKIP_IOS" = "0" ]; then
  log "=== TESTFLIGHT BUILD STATE ==="
  for i in $(seq 1 10); do
    ST=$(ssh -o BatchMode=yes "$MAC" "cd ~/asc 2>/dev/null && python3 asc.py get '/v1/builds?filter[app]=6817778138&limit=3&sort=-uploadedDate' 2>/dev/null" \
      | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
for b in d.get('data',[]):
    a=b.get('attributes',{})
    if str(a.get('version'))=='$CODE': print(a.get('processingState'))
" 2>/dev/null)
    [ -n "$ST" ] && { log "testflight build $CODE: $ST"; break; }
    sleep 30
  done
  [ -z "${ST:-}" ] && log "WARN: build $CODE not yet visible in App Store Connect (processing can take 5-15 min)"
fi

log "=================================================="
log "RELEASE OK: $NAME+$CODE"
log "  website   $SITE/download/$NAME-$CODE.apk"
[ "$SKIP_IOS" = "0" ] && log "  testflight build $CODE"
log "=================================================="
