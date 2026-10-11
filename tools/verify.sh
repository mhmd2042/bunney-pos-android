#!/usr/bin/env bash
# tools/verify.sh — run every check that does not need a device.
#
# This is the phase gate. A phase is not done until this is green, because the
# two things most likely to be silently wrong are exactly what it covers: the
# SQL schema (checked against a real SQLite through the CLI) and the pure-Dart
# domain rules (money, permissions, PIN hashing).
#
# What it does NOT cover, and why:
#   * Database encryption — needs SQLCipher, which is only linked in the Android
#     build. See test/device/README.md.
#   * Layout geometry — needs a rendering surface. Covered by
#     `flutter test test/widget/` for the widget tree, and on a device for real
#     font metrics.
#
# Usage:  tools/verify.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

FLUTTER="${FLUTTER:-flutter}"
if ! command -v "$FLUTTER" >/dev/null 2>&1; then
  for candidate in "$HOME/development/flutter/bin/flutter" /opt/flutter/bin/flutter; do
    [ -x "$candidate" ] && FLUTTER="$candidate" && break
  done
fi
if ! command -v "$FLUTTER" >/dev/null 2>&1 && [ ! -x "$FLUTTER" ]; then
  echo "flutter not found; set FLUTTER=/path/to/flutter" >&2
  exit 2
fi

FAILED=0

echo "=============================================================="
echo " 1/3  SQL schema (real SQLite, via the CLI)"
echo "=============================================================="
if ./tools/verify_schema.sh; then :; else FAILED=1; fi

echo
echo "=============================================================="
echo " 2/3  Static analysis"
echo "=============================================================="
if "$FLUTTER" analyze --no-fatal-infos 2>&1 | tail -20; then :; else FAILED=1; fi

echo
echo "=============================================================="
echo " 3/3  Dart tests (domain + data, no device)"
echo "=============================================================="
if "$FLUTTER" test 2>&1 | tail -8; then :; else FAILED=1; fi

echo
echo "=============================================================="
if [ "$FAILED" = "0" ]; then
  echo " RESULT: all checks passed"
else
  echo " RESULT: FAILURES — see above"
fi
echo "=============================================================="
exit "$FAILED"
