#!/usr/bin/env bash
#
# Builds Sajadah and packages it as a distributable .dmg.
#
#   ./scripts/release.sh 1.0.0
#   ./scripts/release.sh 1.0.0 --keep-signature   # build with your dev cert instead
#
# Requires no signing certificate: it builds and signs ad-hoc, which is what lets the same
# script run unchanged in CI.
#
# The DMG is NOT notarized — that needs a paid Apple Developer Program membership and a
# "Developer ID Application" certificate. See the Gatekeeper note printed at the end.
#
set -euo pipefail

# xcode-select may point at the Command Line Tools, where xcodebuild does not exist. Setting
# this here means the script works without touching the machine's global configuration
# (which would need sudo).
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION="${1:-}"
KEEP_SIGNATURE=false
[[ "${2:-}" == "--keep-signature" ]] && KEEP_SIGNATURE=true

if [[ -z "$VERSION" ]]; then
    echo "usage: $0 <version> [--keep-signature]" >&2
    echo "  e.g. $0 1.0.0" >&2
    exit 1
fi

if [[ ! -d Sajadah.xcodeproj ]]; then
    echo "error: run this from the repository root." >&2
    exit 1
fi

PROJECT=Sajadah.xcodeproj/project.pbxproj
BUILD_DIR=build
STAGE="$BUILD_DIR/dmg"
APP="$BUILD_DIR/Build/Products/Release/Sajadah.app"
DMG="$BUILD_DIR/Sajadah-$VERSION.dmg"

# ─── Version ──────────────────────────────────────────────────────────────────────────────
# Both keys appear once per build configuration. agvtool is not usable here: the project has
# no VERSIONING_SYSTEM, so `agvtool new-version` would silently do nothing.
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
echo "==> Setting version $VERSION (build $BUILD_NUMBER)"
sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $VERSION;/g" "$PROJECT"
sed -i '' "s/CURRENT_PROJECT_VERSION = .*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PROJECT"

# ─── Build ────────────────────────────────────────────────────────────────────────────────
echo "==> Building Release"
rm -rf "$BUILD_DIR/Build" "$STAGE"

# Build ad-hoc rather than with a development certificate. Two reasons: the product gets
# re-signed ad-hoc below anyway, so signing twice is wasted work; and it means this script
# produces byte-for-byte the same signing outcome on a CI runner that has no keychain, no
# certificate and no Apple ID as it does on the author's Mac.
#
# DEVELOPMENT_TEAM is deliberately NOT overridden here — the project already carries it, and
# $(TeamIdentifierPrefix) in the entitlements expands from it even with no certificate present
# (verified). Hardcoding it would give every fork the original author's App Group.
SIGN_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER="")
[[ "$KEEP_SIGNATURE" == true ]] && SIGN_ARGS=()

xcodebuild \
    -project Sajadah.xcodeproj \
    -scheme Sajadah \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    "${SIGN_ARGS[@]}" \
    build \
    | grep -E "error:|warning:|BUILD" || true

[[ -d "$APP" ]] || { echo "error: build produced no app at $APP" >&2; exit 1; }

# ─── Signing ──────────────────────────────────────────────────────────────────────────────
if [[ "$KEEP_SIGNATURE" == true ]]; then
    echo "==> Keeping the build's own signature (--keep-signature)"
else
    # Re-sign even though the build was already ad-hoc: Xcode injects get-task-allow into
    # Release builds regardless of signing style, and stripping it means re-sealing.
    #
    # Entitlements are read back out of the built product rather than from the source .plist,
    # because the source still contains the literal $(TeamIdentifierPrefix) and only the built
    # copy has it expanded. Dropping them would take the App Group with them.
    echo "==> Re-signing ad-hoc"
    ENT_DIR="$(mktemp -d)"

    sign_adhoc() {
        local target="$1" name="$2"
        codesign -d --entitlements - --xml "$target" > "$ENT_DIR/$name.plist" 2>/dev/null || true
        # Xcode injects get-task-allow into every build it signs with a development
        # certificate. It lets any process attach a debugger to the app, and has no business
        # in something people download.
        /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" \
            "$ENT_DIR/$name.plist" >/dev/null 2>&1 || true

        if [[ -s "$ENT_DIR/$name.plist" ]]; then
            codesign --force --sign - --options runtime --timestamp=none \
                     --entitlements "$ENT_DIR/$name.plist" "$target"
        else
            codesign --force --sign - --options runtime --timestamp=none "$target"
        fi
    }

    # Inside-out: nested code must be signed before its container, or the container's seal is
    # invalidated the moment the nested code changes. --deep is deprecated and gets this wrong.
    while IFS= read -r appex; do
        sign_adhoc "$appex" "$(basename "$appex")"
    done < <(find "$APP/Contents" -name "*.appex" -maxdepth 3)
    sign_adhoc "$APP" "Sajadah"
fi

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

# ─── Package ──────────────────────────────────────────────────────────────────────────────
echo "==> Packaging DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
if command -v create-dmg >/dev/null 2>&1; then
    # Prettier window: positioned icons and a sensible size. Optional — brew install create-dmg
    create-dmg \
        --volname "Sajadah $VERSION" \
        --window-size 540 380 \
        --icon-size 110 \
        --icon "Sajadah.app" 140 180 \
        --app-drop-link 400 180 \
        --no-internet-enable \
        "$DMG" "$STAGE" >/dev/null
else
    hdiutil create \
        -volname "Sajadah $VERSION" \
        -srcfolder "$STAGE" \
        -ov -format UDZO \
        "$DMG" >/dev/null
fi

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"

cat <<EOF

────────────────────────────────────────────────────────────────────────
  $DMG  ($SIZE)
  SHA-256  $SHA

  This build is ad-hoc signed and NOT notarized, so Gatekeeper will
  block it on first launch. Tell users to run:

      xattr -dr com.apple.quarantine /Applications/Sajadah.app

  Upload the DMG at:
  https://github.com/shaheem-pp/sajadah-macos/releases/new?tag=v$VERSION
────────────────────────────────────────────────────────────────────────
EOF
