#!/usr/bin/env bash
set -euo pipefail

# NeedleBar - Needle 3 Engine Fetcher
# Downloads official pre-compiled macOS arm64 engine (libneedle3.dylib, needle runner)
# and base 2-bit quantized weights (needle3.cact) into standard cache.

CACHE_DIR="${HOME}/.cache/cactus-needle/v3/3.0.1"
mkdir -p "${CACHE_DIR}"

echo "================================================="
echo " NeedleBar - Fetching Needle 3 macOS Engine"
echo " Destination: ${CACHE_DIR}"
echo "================================================="

HF_BASE="https://huggingface.co/Cactus-Compute/needle3/resolve/main"

# 1. Fetch Model Weights (needle3.cact ~34MB)
if [ ! -f "${CACHE_DIR}/needle3.cact" ]; then
    echo "Downloading needle3.cact model weights (34MB)..."
    curl -L --progress-bar "${HF_BASE}/needle3.cact" -o "${CACHE_DIR}/needle3.cact"
else
    echo "✓ needle3.cact already present."
fi

# 2. Fetch Native CLI Runner
if [ ! -f "${CACHE_DIR}/needle" ]; then
    echo "Downloading macos-arm64 needle CLI runner..."
    curl -L -s "${HF_BASE}/macos-arm64/needle" -o "${CACHE_DIR}/needle"
    chmod +x "${CACHE_DIR}/needle"
else
    echo "✓ needle runner already present."
fi

# 3. Fetch Native Dynamic Library (libneedle3.dylib)
if [ ! -f "${CACHE_DIR}/libneedle3.dylib" ]; then
    echo "Downloading and extracting libneedle3.dylib from wheel..."
    TMP_ZIP="/tmp/needle_wheel_fetch.zip"
    curl -L -s "${HF_BASE}/python/cactus_needle-3.0.1-py3-none-macosx_11_0_arm64.whl" -o "${TMP_ZIP}"
    unzip -p "${TMP_ZIP}" needle/libneedle3.dylib > "${CACHE_DIR}/libneedle3.dylib"
    rm -f "${TMP_ZIP}"
else
    echo "✓ libneedle3.dylib already present."
fi

echo "================================================="
echo "✓ Needle 3 Engine ready for NeedleBar!"
echo "  Weights: ${CACHE_DIR}/needle3.cact ($(du -h "${CACHE_DIR}/needle3.cact" | cut -f1))"
echo "  Dynamic Lib: ${CACHE_DIR}/libneedle3.dylib"
echo "  CLI Runner:  ${CACHE_DIR}/needle"
echo "================================================="
