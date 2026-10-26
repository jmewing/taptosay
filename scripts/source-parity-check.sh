#!/bin/bash
# source-parity-check.sh — prove Android and iOS are built from the same code.
#
# Jeremy, 2026-10-26: "We don't want shit in one app that is not in the other.
# Update both fucking programs at the same time."
#
# Compares the SHARED application logic between the build host (olympus) and the
# iOS build host (the Mac). Exits non-zero on any difference, so a stale Mac
# checkout can never silently ship an app that differs from the Android one.
#
# What is compared: lib/**.dart + pubspec.yaml — the actual app behaviour, the
# only thing that could make one app "have shit the other doesn't".
#
# What is NOT compared, deliberately:
#   android/local.properties   machine-specific sdk.dir
#   ios/Flutter/ephemeral/**   Swift Package Manager scratch, regenerated
#   Pods/, build/, .dart_tool/ build outputs
#
# Usage:  source-parity-check.sh [/path/on/olympus] [mac-host]
set -uo pipefail

SRC="${1:-/srv/taptosay}"
MAC="${2:-jmewing@100.123.184.92}"
MACSRC='~/taptosay'

# Relative-path digest: cd in first, so different absolute paths on the two
# hosts still hash equal. (Hashing absolute paths was the bug that made an
# identical pair report as mismatched.)
digest_local() {
  ( cd "$1" || exit 1
    { find lib -type f -name '*.dart' | LC_ALL=C sort
      echo pubspec.yaml
    } | while IFS= read -r f; do
          [ -f "$f" ] && printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"
        done | sha256sum | cut -d' ' -f1 )
}

digest_mac() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$MAC" '
    cd '"$MACSRC"' || exit 1
    { find lib -type f -name "*.dart" | LC_ALL=C sort
      echo pubspec.yaml
    } | while IFS= read -r f; do
          [ -f "$f" ] && printf "%s  %s\n" "$(shasum -a 256 "$f" | cut -d" " -f1)" "$f"
        done | shasum -a 256 | cut -d" " -f1' 2>/dev/null | tr -d '\r'
}

L=$(digest_local "$SRC")
R=$(digest_mac)

if [ -z "$L" ]; then echo "PARITY FAIL: could not hash $SRC"; exit 1; fi
if [ -z "$R" ]; then echo "PARITY FAIL: could not hash $MACSRC on $MAC"; exit 1; fi

if [ "$L" = "$R" ]; then
  echo "PARITY OK  shared code identical: $L"
  exit 0
fi

echo "PARITY FAIL: the two apps would differ"
echo "  olympus $L"
echo "  mac     $R"
echo
echo "Per-file differences:"
# enumerate the actual differing files so the fix is obvious
diff <(
  cd "$SRC" && { find lib -type f -name '*.dart' | LC_ALL=C sort; echo pubspec.yaml; } \
    | while IFS= read -r f; do [ -f "$f" ] && printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"; done
) <(
  ssh -o BatchMode=yes "$MAC" '
    cd '"$MACSRC"' && { find lib -type f -name "*.dart" | LC_ALL=C sort; echo pubspec.yaml; } \
      | while IFS= read -r f; do [ -f "$f" ] && printf "%s  %s\n" "$(shasum -a 256 "$f" | cut -d" " -f1)" "$f"; done' 2>/dev/null \
    | tr -d '\r'
) 2>/dev/null | grep -E '^[<>]' | sed 's/^/  /'
exit 1
