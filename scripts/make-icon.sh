#!/usr/bin/env bash
# Regenerates the app icon and README brand assets from Shared/Design/.
# Run from the repository root.
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BIN="$(mktemp -d)/makeicon"

echo "Compiling icon generator against the app's own shapes…"
xcrun swiftc -O \
    Shared/Models/Prayer.swift \
    Shared/Design/Theme.swift \
    Shared/Design/IslamicOrnaments.swift \
    scripts/MakeIcon.swift \
    -o "$BIN"

echo "Rendering:"
"$BIN"
echo "Done."
