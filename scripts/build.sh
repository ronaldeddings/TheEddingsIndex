#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="The Eddings Index"
BUNDLE_NAME="TheEddingsIndex"
BINARY_NAME="TheEddingsIndex"
SIGNING_IDENTITY="${EDDINGSINDEX_SIGNING_IDENTITY:-Developer ID Application: HACKER VALLEY MEDIA, LLC (TPWBZD35WW)}"
VERSION="${VERSION:-1.0.0}"
INFO_PLIST="$PROJECT_DIR/Sources/EddingsApp/AppInfo.plist"
ENTITLEMENTS="$PROJECT_DIR/Sources/EddingsApp/EddingsIndex.entitlements"
APP_BUNDLE="$PROJECT_DIR/.build/${BUNDLE_NAME}.app"
RUN_ID=$(date +"%Y%m%d-%H%M%S")

BUILD_CONFIG="release"
DO_RUN=false
DO_INSTALL=false
DO_DMG=true
DO_NOTARIZE=false

for arg in "$@"; do
    case "$arg" in
        debug)      BUILD_CONFIG="debug" ;;
        run)        DO_RUN=true; DO_DMG=false ;;
        install)    DO_INSTALL=true ;;
        notarize)   DO_NOTARIZE=true ;;
        no-dmg)     DO_DMG=false ;;
        *)          echo "Unknown arg: $arg"; echo "Usage: $0 [debug] [run] [install] [notarize] [no-dmg]"; exit 1 ;;
    esac
done

echo "══════════════════════════════════════════════════"
echo "  ${APP_NAME} — Build Pipeline"
echo "══════════════════════════════════════════════════"
echo "  Config:    ${BUILD_CONFIG}"
echo "  Version:   ${VERSION}"
echo "  Run ID:    ${RUN_ID}"
echo "  Signing:   ${SIGNING_IDENTITY}"
echo "══════════════════════════════════════════════════"

# ── Step 1: Prerequisites ────────────────────────────
echo ""
echo "▸ Step 1: Checking prerequisites..."

if ! command -v swift &>/dev/null; then
    echo "  ✗ Swift not found. Install Xcode or Swift toolchain."
    exit 1
fi
echo "  ✓ Swift $(swift --version 2>&1 | head -1 | sed 's/.*version //' | sed 's/ .*//')"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
    echo "  ✗ Signing identity not found: $SIGNING_IDENTITY"
    exit 1
fi
echo "  ✓ Signing identity found"

if [ ! -f "$INFO_PLIST" ]; then
    echo "  ✗ Info.plist not found: $INFO_PLIST"
    exit 1
fi
echo "  ✓ Info.plist"

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "  ✗ Entitlements not found: $ENTITLEMENTS"
    exit 1
fi
echo "  ✓ Entitlements"

# ── Step 2: Kill running instance ────────────────────
echo ""
echo "▸ Step 2: Stopping running instances..."
pkill -f "$BINARY_NAME" 2>/dev/null && echo "  ✓ Stopped running instance" && sleep 1 || echo "  · No running instance"

# ── Step 3: Swift build ──────────────────────────────
echo ""
echo "▸ Step 3: Building ($BUILD_CONFIG)..."
cd "$PROJECT_DIR"

if [ "$BUILD_CONFIG" = "release" ]; then
    swift build -c release 2>&1 | tail -5
    BUILT_BINARY="$PROJECT_DIR/.build/release/$BINARY_NAME"
else
    swift build 2>&1 | tail -5
    BUILT_BINARY="$PROJECT_DIR/.build/debug/$BINARY_NAME"
fi

if [ ! -f "$BUILT_BINARY" ]; then
    echo "  ✗ Binary not found: $BUILT_BINARY"
    exit 1
fi
BINARY_SIZE=$(du -h "$BUILT_BINARY" | cut -f1)
echo "  ✓ Binary built: $BINARY_SIZE"

# Also build ei-cli
if [ "$BUILD_CONFIG" = "release" ]; then
    CLI_BINARY="$PROJECT_DIR/.build/release/ei-cli"
else
    CLI_BINARY="$PROJECT_DIR/.build/debug/ei-cli"
fi
if [ -f "$CLI_BINARY" ]; then
    echo "  ✓ ei-cli built: $(du -h "$CLI_BINARY" | cut -f1)"
fi

# ── Step 4: Assemble .app bundle ─────────────────────
echo ""
echo "▸ Step 4: Assembling .app bundle..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILT_BINARY" "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"
echo "  ✓ Binary copied"

cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
echo "  ✓ Info.plist copied"

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"
echo "  ✓ PkgInfo created"

if [ -f "$PROJECT_DIR/Sources/EddingsApp/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Sources/EddingsApp/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "  ✓ App icon copied"
else
    echo "  · No app icon found (skipping)"
fi

echo "  ✓ App bundle assembled at: $APP_BUNDLE"

# ── Step 5: Verify binary linkage ────────────────────
echo ""
echo "▸ Step 5: Verifying binary linkage..."
EXTERNAL_DEPS=$(otool -L "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME" 2>/dev/null | grep -v "/usr/lib" | grep -v "/System" | grep -v "$BINARY_NAME" | grep -v "^$APP_BUNDLE" || true)
if [ -n "$EXTERNAL_DEPS" ]; then
    echo "  ⚠ External dependencies detected:"
    echo "$EXTERNAL_DEPS" | while read -r line; do echo "    $line"; done
else
    echo "  ✓ No external dylib dependencies (pure Swift)"
fi

# ── Step 6: Code sign ────────────────────────────────
echo ""
echo "▸ Step 6: Signing app bundle..."

codesign --force \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    --options runtime \
    "$APP_BUNDLE"

echo "  ✓ App bundle signed"

# ── Step 7: Verify signature ─────────────────────────
echo ""
echo "▸ Step 7: Verifying signature..."

if codesign --verify --verbose=2 "$APP_BUNDLE" 2>&1; then
    echo "  ✓ Signature valid"
else
    echo "  ✗ Signature verification failed"
    exit 1
fi

TEAM_ID=$(codesign --display --verbose=2 "$APP_BUNDLE" 2>&1 | grep TeamIdentifier | awk -F= '{print $2}')
echo "  ✓ Team: $TEAM_ID"

# ── Step 8: Create DMG ───────────────────────────────
if [ "$DO_DMG" = true ]; then
    echo ""
    echo "▸ Step 8: Creating DMG..."

    DMG_DIR="$PROJECT_DIR/dist/runs/${RUN_ID}"
    mkdir -p "$DMG_DIR"
    DMG_NAME="${BUNDLE_NAME}-${VERSION}-${RUN_ID}.dmg"
    OUTPUT_DMG="$DMG_DIR/$DMG_NAME"

    STAGING_DIR="/tmp/eddingsindex-dmg-staging"
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"
    cp -R "$APP_BUNDLE" "$STAGING_DIR/${APP_NAME}.app"
    ln -s /Applications "$STAGING_DIR/Applications"

    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$STAGING_DIR" \
        -ov -format UDZO \
        -imagekey zlib-level=9 \
        "$OUTPUT_DMG" 2>/dev/null

    rm -rf "$STAGING_DIR"

    DMG_SIZE=$(du -h "$OUTPUT_DMG" | cut -f1)
    echo "  ✓ DMG created: $OUTPUT_DMG ($DMG_SIZE)"
fi

# ── Step 9: Install to /Applications ─────────────────
if [ "$DO_INSTALL" = true ]; then
    echo ""
    echo "▸ Step 9: Installing to /Applications..."

    if [ -d "/Applications/${APP_NAME}.app" ]; then
        rm -rf "/Applications/${APP_NAME}.app"
        echo "  · Removed existing installation"
    fi

    cp -R "$APP_BUNDLE" "/Applications/${APP_NAME}.app"
    echo "  ✓ Installed to /Applications/${APP_NAME}.app"
fi

# ── Step 10: Notarize (optional) ─────────────────────
if [ "$DO_NOTARIZE" = true ]; then
    echo ""
    echo "▸ Step 10: Notarizing..."

    if [ -z "${APPLE_ID:-}" ] || [ -z "${APP_PASSWORD:-}" ] || [ -z "${NOTARIZE_TEAM_ID:-}" ]; then
        echo "  ✗ Set APPLE_ID, APP_PASSWORD, NOTARIZE_TEAM_ID env vars for notarization"
        exit 1
    fi

    ZIP_PATH="/tmp/${BUNDLE_NAME}-notarize.zip"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$NOTARIZE_TEAM_ID" \
        --wait --timeout 30m

    xcrun stapler staple "$APP_BUNDLE"
    echo "  ✓ Notarization complete"

    rm -f "$ZIP_PATH"
fi

# ── Step 11: Run (optional) ──────────────────────────
if [ "$DO_RUN" = true ]; then
    echo ""
    echo "▸ Launching ${APP_NAME}..."
    # Try 'open' first (works for notarized apps and Xcode-built bundles)
    if open "$APP_BUNDLE" 2>/dev/null; then
        echo "  ✓ Launched via open"
    else
        echo "  · open failed (unnotarized on macOS Tahoe)"
        echo "  · Launching raw binary for development..."
        "$BUILT_BINARY" &
        APP_PID=$!
        sleep 2
        if kill -0 $APP_PID 2>/dev/null; then
            echo "  ✓ Launched (PID: $APP_PID)"
            echo "  Note: Running as raw binary, not .app bundle."
            echo "  For .app launch: notarize with './scripts/build.sh notarize'"
        else
            echo "  ✗ Launch failed"
            exit 1
        fi
    fi
fi

# ── Summary ──────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════"
echo "  ✓ BUILD COMPLETE"
echo "══════════════════════════════════════════════════"
echo "  App:     $APP_BUNDLE"
echo "  Binary:  $BINARY_SIZE"
if [ "$DO_DMG" = true ] && [ -f "${OUTPUT_DMG:-/dev/null}" ]; then
    echo "  DMG:     $OUTPUT_DMG ($DMG_SIZE)"
fi
if [ "$DO_INSTALL" = true ]; then
    echo "  Install: /Applications/${APP_NAME}.app"
fi
echo "══════════════════════════════════════════════════"
