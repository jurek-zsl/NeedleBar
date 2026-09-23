#!/usr/bin/env bash
set -euo pipefail

# NeedleBar - Build and Package macOS Application Bundle
# Creates a standalone, self-contained NeedleBar.app

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="/tmp/needlebar-build"
PROJECT_APP_LINK="${PROJECT_DIR}/NeedleBar.app"
# Documents may be managed by a file provider that adds Finder metadata after
# signing, invalidating the bundle. Keep the runnable app in Applications.
APP_BUNDLE="${NEEDLEBAR_APP_OUTPUT:-${HOME}/Applications/NeedleBar.app}"
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
STAGING_BUNDLE="/tmp/NeedleBar.app"
rm -rf "${STAGING_BUNDLE}" "${APP_BUNDLE}"
mkdir -p "${STAGING_BUNDLE}/Contents/MacOS"
mkdir -p "${STAGING_BUNDLE}/Contents/Resources"
mkdir -p "${STAGING_BUNDLE}/Contents/Frameworks"

cp "${BIN_PATH}" "${STAGING_BUNDLE}/Contents/MacOS/NeedleBarApp"
cp "${PROJECT_DIR}/Sources/NeedleBarApp/Info.plist" "${STAGING_BUNDLE}/Contents/Info.plist"

# 3. Bundle Needle 3 Engine & Weights if available
if [ -f "${CACHE_DIR}/libneedle3.dylib" ]; then
    echo "Bundling libneedle3.dylib into Frameworks..."
    cp "${CACHE_DIR}/libneedle3.dylib" "${STAGING_BUNDLE}/Contents/Frameworks/libneedle3.dylib"
fi

if [ -f "${CACHE_DIR}/needle3.cact" ]; then
    echo "Bundling needle3.cact into Resources..."
    cp "${CACHE_DIR}/needle3.cact" "${STAGING_BUNDLE}/Contents/Resources/needle3.cact"
fi

# 4. Codesign in clean /tmp. Accessibility approval is tied to the app's
# designated requirement, so prefer a stable Apple Development identity.
# A plain ad-hoc signature defaults to a changing CDHash requirement and makes
# macOS forget Accessibility approval after every rebuild.
echo "Codesigning bundle..."
xattr -cr "${STAGING_BUNDLE}"

SIGNING_IDENTITY="${NEEDLEBAR_CODESIGN_IDENTITY:-}"
if [ -z "${SIGNING_IDENTITY}" ]; then
    SIGNING_IDENTITY="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
            | head -n 1
    )"
fi

if [ -n "${SIGNING_IDENTITY}" ]; then
    echo "Using stable signing identity: ${SIGNING_IDENTITY}"
    if [ -f "${STAGING_BUNDLE}/Contents/Frameworks/libneedle3.dylib" ]; then
        codesign --force --sign "${SIGNING_IDENTITY}" \
            "${STAGING_BUNDLE}/Contents/Frameworks/libneedle3.dylib"
    fi
    codesign --force --sign "${SIGNING_IDENTITY}" \
        --identifier com.needlebar.NeedleBar \
        "${STAGING_BUNDLE}"
else
    echo "No Apple Development identity found; using a stable local requirement."
    if [ -f "${STAGING_BUNDLE}/Contents/Frameworks/libneedle3.dylib" ]; then
        codesign --force --sign - \
            "${STAGING_BUNDLE}/Contents/Frameworks/libneedle3.dylib"
    fi
    codesign --force --sign - \
        --identifier com.needlebar.NeedleBar \
        --requirements '=designated => identifier "com.needlebar.NeedleBar"' \
        "${STAGING_BUNDLE}"
fi

codesign --verify --deep --strict "${STAGING_BUNDLE}"

# 5. Install outside file-provider-managed project folders, then keep a stable
# project-local link for convenience.
mkdir -p "$(dirname "${APP_BUNDLE}")"
rm -rf "${APP_BUNDLE}"
mv "${STAGING_BUNDLE}" "${APP_BUNDLE}"
xattr -cr "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"

if [ "${PROJECT_APP_LINK}" != "${APP_BUNDLE}" ]; then
    rm -rf "${PROJECT_APP_LINK}"
    ln -s "${APP_BUNDLE}" "${PROJECT_APP_LINK}"
fi

echo "================================================="
echo "✓ NeedleBar.app successfully built!"
echo "  Location: ${APP_BUNDLE}"
echo ""
echo "To run:"
echo "  open \"${APP_BUNDLE}\""
echo ""
echo "To install to Applications:"
echo "  Already installed for this user in ${APP_BUNDLE}"
echo "================================================="
