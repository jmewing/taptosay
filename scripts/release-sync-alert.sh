#!/bin/bash
# release-sync-alert.sh — daily guard for the TapToSay release channel.
#
# Prints NOTHING when Android-website / iOS-TestFlight / local build all agree.
# Prints a short alert when they don't. Always exits 0.
#
# Why the wrapper: this runs as a `command` automation payload, where stdout IS
# the delivered message and an empty stdout is intentional silence. Keeping the
# exit code at 0 means a genuine disagreement still delivers its alert instead
# of being swallowed as a failed run.
#
# The real logic lives in check-release-sync.sh so it can also be run by hand.
set -uo pipefail

OUT=$(bash /srv/taptosay/scripts/check-release-sync.sh 2>&1)
RC=$?

if [ "$RC" -ne 0 ]; then
  echo "⚠️ TapToSay release out of sync"
  printf '%s\n' "$OUT" | grep -vE '^\s*$' | head -6
else
  # Agreement: silence. (Empty output = the automation delivers nothing.)
  :
fi

exit 0
