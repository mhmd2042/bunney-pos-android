#!/usr/bin/env bash
# tools/diagnose_device.sh — read the real Dart error off a connected device.
#
# The Flutter red error screen does not always reach logcat: an exception thrown
# during build() is caught by the framework and painted, and the text is only on
# screen. This pulls the widget-tree dump and the logcat buffer together, which
# is usually enough to name the widget and the assertion.
#
# Usage:  tools/diagnose_device.sh [package]
set -uo pipefail

PKG="${1:-com.bunney.bunney_pos_android}"
ADB="${ADB:-$HOME/Android/Sdk/platform-tools/adb}"
[ -x "$ADB" ] || ADB="adb"

echo "=== 1. device ==="
"$ADB" devices | tail -n +2

echo
echo "=== 2. restart the app and capture the first frames ==="
"$ADB" logcat -c
"$ADB" shell am force-stop "$PKG"
sleep 2
"$ADB" shell am start -n "$PKG/.MainActivity" >/dev/null
sleep 18

echo
echo "=== 3. Dart errors in logcat ==="
"$ADB" logcat -d | grep -iE "flutter|dart" \
  | grep -viE "Impeller|opt-out|issue/new|Action Required|flag or the|entry\.|These options|the issue|^$" \
  | tail -30

echo
echo "=== 4. framework exceptions (any tag) ==="
"$ADB" logcat -d | grep -iE "EXCEPTION CAUGHT|Another exception|RenderFlex|Failed assertion|NoSuchMethod|LateInitialization|Null check|type '" | tail -25

echo
echo "=== 5. is the screen the red error page? ==="
"$ADB" shell screencap -p /sdcard/_diag.png >/dev/null 2>&1
"$ADB" pull /sdcard/_diag.png /tmp/_diag.png >/dev/null 2>&1
if [ -f /tmp/_diag.png ]; then
  echo "  screenshot: /tmp/_diag.png ($(stat -c%s /tmp/_diag.png) bytes)"
else
  echo "  screenshot pull failed"
fi

echo
echo "=== 6. app process ==="
"$ADB" shell "ps | grep ${PKG##*.}" | head -3
