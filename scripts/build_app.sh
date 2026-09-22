#!/usr/bin/env bash
set -euo pipefail

# NeedleBar - Build and Package macOS Application Bundle
# Creates a standalone, self-contained NeedleBar.app

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="/tmp/needlebar-build"
APP_BUNDLE="${PROJECT_DIR}/NeedleBar.app"
CACHE_DIR="${HOME}/.cache/cactus-needle/v3/3.0.1"

echo "================================================="
echo " Building NeedleBar for macOS (Release)"
echo "================================================="

cd "${PROJECT_DIR}"

# 1. Compile Release Binary
swift build -c release --build-path "${BUILD_DIR}"

BIN_PATH="${BUILD_DIR}/release/NeedleBarApp"
if [ ! -f "${BIN_PATH}" ]; then
    # Fallback check
    BIN_PATH="${BUILD_DIR}/arm64-apple-macosx/release/NeedleBarApp"
fi

if [ ! -f "${BIN_PATH}" ]; then
    echo "Error: NeedleBarApp binary not found in build directory."
    exit 1
fi

echo "✓ Compiled binary: ${BIN_PATH}"

# 2. Assemble App Bundle
echo "Assembling NeedleBar.app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
mkdir -p "${APP_BUNDLE}/Contents/Frameworks"

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/NeedleBarApp"
cp "${PROJECT_DIR}/Sources/NeedleBarApp/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# 3. Bundle Needle 3 Engine & Weights if available
if [ -f "${CACHE_DIR}/libneedle3.dylib" ]; then
    echo "Bundling libneedle3.dylib into Frameworks..."
    cp "${CACHE_DIR}/libneedle3.dylib" "${APP_BUNDLE}/Contents/Frameworks/libneedle3.dylib"
fi

if [ -f "${CACHE_DIR}/needle3.cact" ]; then
    echo "Bundling needle3.cact into Resources..."
    cp "${CACHE_DIR}/needle3.cact" "${APP_BUNDLE}/Contents/Resources/needle3.cact"
fi

# 4. Ad-hoc Codesign
echo "Codesigning bundle..."
xattr -cr "${APP_BUNDLE}"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "================================================="
echo "✓ NeedleBar.app successfully built!"
echo "  Location: ${APP_BUNDLE}"
echo ""
echo "To run:"
echo "  open \"${APP_BUNDLE}\""
echo ""
echo "To install to Applications:"
echo "  cp -R \"${APP_BUNDLE}\" /Applications/"
echo "================================================="
