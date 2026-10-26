#!/bin/bash
# build-both-platforms.sh — build TapToSay for Android AND iOS from ONE version.
#
# Jeremy, 2026-10-26: "You have to build for both platforms at the same time so
# that the damn revision always matches."
#
# Runs on OLYMPUS. Bumps pubspec version ONCE, syncs that exact source to the
# Mac, then builds:
#   * Android APK + AAB here (olympus toolchain)
#   * iOS release Runner.app on the Mac (--no-codesign; signing is separate)
#
# The version is read BACK from each artifact and compared, so a mismatch or a
# stale build fails loudly instead of shipping two different revisions.
set -uo pipefail

SRC=/srv/taptosay
MAC=jmewing@100.123.184.92
MACSRC='~/taptosay'
TC=/home/jmewing/android-toolchain
LOGDIR=$SRC/build-logs
mkdir -p "$LOGDIR"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
fail() { log "FAIL: $*"; exit 1; }

# ---- 1. one version bump, used by both platforms ---------------------------
cd "$SRC" || fail "no $SRC"
OLD=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
NAME=${OLD%%+*}; CODE=${OLD##*+}
NEWCODE=$((CODE + 1))
NEW="$NAME+$NEWCODE"
sed -i "s/^version: .*/version: $NEW/" pubspec.yaml
log "version: $OLD -> $NEW"

# ---- 2. Android (local) ----------------------------------------------------
export JAVA_HOME=$TC/jdk ANDROID_HOME=$TC/android-sdk ANDROID_SDK_ROOT=$TC/android-sdk
export PATH=$TC/flutter/bin:$TC/jdk/bin:$TC/android-sdk/platform-tools:$PATH
sed -i 's#^sdk.dir=.*#sdk.dir=/home/jmewing/android-toolchain/android-sdk#' android/local.properties 2>/dev/null

log "building Android APK + AAB..."
flutter build apk --release  >"$LOGDIR/android-apk-$NEWCODE.log" 2>&1 || fail "apk build (see $LOGDIR/android-apk-$NEWCODE.log)"
flutter build appbundle --release >"$LOGDIR/android-aab-$NEWCODE.log" 2>&1 || fail "aab build"

APK=$SRC/build/app/outputs/flutter-apk/app-release.apk
AAB=$SRC/build/app/outputs/bundle/release/app-release.aab
[ -f "$APK" ] || fail "APK missing"
[ -f "$AAB" ] || fail "AAB missing"
log "android: apk=$(stat -c%s "$APK") aab=$(stat -c%s "$AAB")"

# ---- 3. push the SAME source to the Mac, then build iOS --------------------
log "syncing source to Mac..."
rsync -az --delete \
  --exclude 'build/' --exclude '.dart_tool/' --exclude '.git/' \
  --exclude 'android/local.properties' \
  -e "ssh -o BatchMode=yes -o ConnectTimeout=10" \
  "$SRC/" "$MAC:$MACSRC/" || fail "rsync to Mac"

MACVER=$(ssh -o BatchMode=yes "$MAC" "grep '^version:' $MACSRC/pubspec.yaml | awk '{print \$2}'")
[ "$MACVER" = "$NEW" ] || fail "Mac has version '$MACVER', expected '$NEW'"
log "mac version confirmed: $MACVER"

# ---- 3b. CODE PARITY: refuse to build iOS from different code than Android --
# Jeremy, 2026-10-26: "We don't want shit in one app that is not in the other."
# A matching version number is not enough -- the CODE has to match. This
# compares every shared source file between the two hosts and aborts on any
# difference, so a stale Mac checkout can never ship a divergent app.
log "checking source parity..."
if ! bash "$SRC/scripts/source-parity-check.sh" "$SRC" "$MAC" 2>&1 | sed 's/^/    /'; then
  fail "source parity check failed -- the two apps would differ"
fi
log "source parity confirmed"

# ---- 3b. prove BOTH platforms are built from IDENTICAL source -------------
# Jeremy, 2026-10-26: "We don't want shit in one app that is not in the other."
# The version matching is not enough -- the CODE must match. Hash every source
# file that goes into the binary and compare; refuse to build iOS from anything
# other than the exact bytes Android was built from.

log "building iOS on Mac (release, no codesign)..."
ssh -o BatchMode=yes "$MAC" "
  export PATH=\$HOME/flutter/bin:/opt/homebrew/bin:\$PATH
  cd $MACSRC || exit 1
  flutter build ios --release --no-codesign
" >"$LOGDIR/ios-$NEWCODE.log" 2>&1 || fail "iOS build (see $LOGDIR/ios-$NEWCODE.log)"

IOSAPP=$(ssh -o BatchMode=yes "$MAC" "ls -d $MACSRC/build/ios/iphoneos/Runner.app 2>/dev/null")
[ -n "$IOSAPP" ] || fail "iOS Runner.app missing on Mac"
log "ios: Runner.app present at $IOSAPP"

# ---- 4. prove both artifacts carry the same version ------------------------
# aapt2 ships with build-tools; plain `aapt` is not on PATH in this toolchain,
# which made this check read empty strings and fail an otherwise good build.
AAPT2=$(find "$TC/android-sdk/build-tools" -name aapt2 2>/dev/null | sort -r | head -1)
[ -n "$AAPT2" ] || fail "aapt2 not found in build-tools"
BADGING=$("$AAPT2" dump badging "$APK" 2>/dev/null | head -1)
ANDROID_VER=$(printf '%s' "$BADGING" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
ANDROID_CODE=$(printf '%s' "$BADGING" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")
IOS_VER=$(ssh -o BatchMode=yes "$MAC" "/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $MACSRC/build/ios/iphoneos/Runner.app/Info.plist 2>/dev/null")
IOS_BUILD=$(ssh -o BatchMode=yes "$MAC" "/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' $MACSRC/build/ios/iphoneos/Runner.app/Info.plist 2>/dev/null")

log "verify  android=${ANDROID_VER:-?}+${ANDROID_CODE:-?}  ios=${IOS_VER:-?}+${IOS_BUILD:-?}  expected=$NEW"
[ "$ANDROID_VER" = "$NAME" ]  || fail "APK versionName '$ANDROID_VER' != '$NAME'"
[ "$ANDROID_CODE" = "$NEWCODE" ] || fail "APK versionCode '$ANDROID_CODE' != '$NEWCODE'"
[ "$IOS_VER" = "$NAME" ]      || fail "iOS short version '$IOS_VER' != '$NAME'"
[ "$IOS_BUILD" = "$NEWCODE" ] || fail "iOS build number '$IOS_BUILD' != '$NEWCODE'"

log "OK: both platforms at $NEW"
log "  APK  $APK"
log "  AAB  $AAB"
log "  iOS  $IOSAPP (unsigned)"
exit 0
