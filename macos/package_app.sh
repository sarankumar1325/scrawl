#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="Scrawl Boards.app"
BUNDLE_ID="com.doodlebug.mac"
APP_PATH="$BUILD_DIR/$APP_NAME"

echo "==> Building web and server assets..."
cd "$PROJECT_ROOT"
npm run build

echo "==> Compiling Swift native release binary..."
cd "$SCRIPT_DIR"
swift build -c release

echo "==> Assembling macOS App Bundle ($APP_NAME)..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources/app"

# 1. Binary
cp "$SCRIPT_DIR/.build/release/Scrawl" "$APP_PATH/Contents/MacOS/Scrawl"
chmod +x "$APP_PATH/Contents/MacOS/Scrawl"

# 2. Metadata & Icon
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
if [ -f "$SCRIPT_DIR/Resources/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

# 3. Web & Server Bundle
cp -R "$PROJECT_ROOT/dist" "$APP_PATH/Contents/Resources/app/dist"
cp "$PROJECT_ROOT/package.json" "$APP_PATH/Contents/Resources/app/package.json"

# 4. Runtime Node Modules
if [ -d "$PROJECT_ROOT/node_modules" ]; then
    echo "==> Packaging runtime node_modules..."
    rsync -a --exclude='.bin' --exclude='.cache' "$PROJECT_ROOT/node_modules" "$APP_PATH/Contents/Resources/app/"
fi

if [ "${SKIP_INSTALL:-0}" = "1" ]; then
    echo "==> Build complete (install skipped): $APP_PATH"
    exit 0
fi

INSTALL_PATH="/Applications/$APP_NAME"
if [ -d "$INSTALL_PATH" ]; then
    EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL_PATH/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$EXISTING_ID" != "$BUNDLE_ID" ]; then
        echo "error: $INSTALL_PATH exists but is not this app (bundle id: ${EXISTING_ID:-unknown}). Not overwriting." >&2
        exit 1
    fi
fi

echo "==> Installing to $INSTALL_PATH..."
rm -rf "$INSTALL_PATH"
cp -R "$APP_PATH" "$INSTALL_PATH"

echo "==> Build and install complete: $INSTALL_PATH"
