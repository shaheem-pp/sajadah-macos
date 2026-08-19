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
STABLE_DMG="$BUILD_DIR/Sajadah.dmg"

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

# Nobody reads a README while staring at a Gatekeeper modal, so the instructions ship inside
# the disk image itself. The leading space in the filename sorts it first by name.
cat > "$STAGE/ Read Me First.txt" <<'READMESH'
Sajadah — installing
====================

1.  Drag Sajadah.app onto the Applications folder in this window.

    Do NOT just double-click it here. Opening the app from this disk
    image is not the same as installing it, and it will fail.

2.  Eject this disk image.

3.  Open Terminal and run this one line:

        xattr -dr com.apple.quarantine /Applications/Sajadah.app

4.  Open Sajadah normally. You only ever do step 3 once.


Why is step 3 necessary?
------------------------

If you skip it, macOS says:

    "Sajadah" Not Opened
    Apple could not verify "Sajadah" is free of malware that may harm
    your Mac or compromise your privacy.

If you see that, click Done — never "Move to Trash" — and do step 3.

That message appears because Sajadah is not notarized by Apple.
Notarizing requires a paid Apple Developer Program membership, which
this project does not have. It is not a statement that anything is
wrong with the app; an unnotarized app and a malicious one produce the
identical warning, which is why the source is public and every release
publishes a SHA-256 you can check.

You can avoid the warning entirely by installing from the terminal
instead, because the quarantine flag is applied by your browser rather
than by macOS:

    curl -fsSL https://github.com/shaheem-pp/sajadah-macos/releases/latest/download/Sajadah.dmg -o /tmp/Sajadah.dmg &&
    hdiutil attach -quiet /tmp/Sajadah.dmg &&
    cp -R /Volumes/Sajadah/Sajadah.app /Applications/ &&
    hdiutil detach -quiet /Volumes/Sajadah &&
    rm /tmp/Sajadah.dmg &&
    open -a Sajadah


Source, issues and licence: https://github.com/shaheem-pp/sajadah-macos
READMESH

rm -f "$DMG"
# The volume name is deliberately NOT versioned: the documented one-line installer copies from
# /Volumes/Sajadah, and that path has to be the same at every release.
if command -v create-dmg >/dev/null 2>&1; then
    # Prettier window: positioned icons and a sensible size. Optional — brew install create-dmg
    create-dmg \
        --volname "Sajadah" \
        --window-size 600 420 \
        --icon-size 110 \
        --icon "Sajadah.app" 150 190 \
        --app-drop-link 450 190 \
        --icon " Read Me First.txt" 300 330 \
        --no-internet-enable \
        "$DMG" "$STAGE" >/dev/null
else
    hdiutil create \
        -volname "Sajadah" \
        -srcfolder "$STAGE" \
        -ov -format UDZO \
        "$DMG" >/dev/null
fi

# A second copy under a fixed name, so releases/latest/download/Sajadah.dmg is a permanent URL.
# Without it the installer one-liner would break at every version bump.
cp "$DMG" "$STABLE_DMG"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"

cat <<EOF

────────────────────────────────────────────────────────────────────────
  $DMG  ($SIZE)
  $STABLE_DMG  (same file, stable name for the latest-download URL)

  SHA-256  $SHA

  This build is ad-hoc signed and NOT notarized, so a browser download
  will be blocked by Gatekeeper on first launch. Installing from the
  terminal avoids that entirely — the quarantine flag comes from the
  browser, not from macOS:

      curl -fsSL https://github.com/shaheem-pp/sajadah-macos/releases/latest/download/Sajadah.dmg -o /tmp/Sajadah.dmg &&
      hdiutil attach -quiet /tmp/Sajadah.dmg &&
      cp -R /Volumes/Sajadah/Sajadah.app /Applications/ &&
      hdiutil detach -quiet /Volumes/Sajadah &&
      rm /tmp/Sajadah.dmg &&
      open -a Sajadah

  For a browser download, the recovery is:

      xattr -dr com.apple.quarantine /Applications/Sajadah.app

  Upload both DMGs at:
  https://github.com/shaheem-pp/sajadah-macos/releases/new?tag=v$VERSION
────────────────────────────────────────────────────────────────────────
EOF
