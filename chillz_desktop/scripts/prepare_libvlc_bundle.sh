#!/bin/bash
# Prepare libVLC bundle for Linux
# This creates a libvlc_bundle_linux directory with all necessary VLC files
# for distribution. Run this on a system with VLC installed.
#
# Usage: ./prepare_libvlc_bundle.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUNDLE_DIR="$PROJECT_DIR/libvlc_bundle_linux"

echo "====================================="
echo "Preparing libVLC Bundle for Linux"
echo "====================================="

# Clean existing bundle
if [ -d "$BUNDLE_DIR" ]; then
    echo "[INFO] Removing existing bundle..."
    rm -rf "$BUNDLE_DIR"
fi

mkdir -p "$BUNDLE_DIR"

# Find VLC libraries
echo "[INFO] Looking for VLC libraries..."

VLC_LIB_PATHS=(
    "/usr/lib/x86_64-linux-gnu"
    "/usr/lib64"
    "/usr/lib"
    "/usr/local/lib"
)

VLC_PLUGIN_PATHS=(
    "/usr/lib/x86_64-linux-gnu/vlc/plugins"
    "/usr/lib64/vlc/plugins"
    "/usr/lib/vlc/plugins"
    "/usr/local/lib/vlc/plugins"
)

# Find and copy main libraries
VLC_FOUND=false
for path in "${VLC_LIB_PATHS[@]}"; do
    if [ -f "$path/libvlc.so.5" ]; then
        echo "[INFO] Found libVLC at: $path"
        
        # Copy main libraries with symlinks resolved (--dereference)
        for lib in libvlc.so libvlc.so.5 libvlc.so.5.* libvlccore.so libvlccore.so.9 libvlccore.so.9.*; do
            for file in "$path"/$lib; do
                if [ -e "$file" ]; then
                    # Use -L to follow symlinks and copy the actual file
                    cp -Lav "$file" "$BUNDLE_DIR/" 2>/dev/null || true
                fi
            done
        done
        
        VLC_FOUND=true
        break
    fi
done

if [ "$VLC_FOUND" = false ]; then
    echo "[ERROR] libVLC not found!"
    echo "[INFO] Install VLC: sudo apt install vlc libvlc-dev"
    exit 1
fi

# Find and copy plugins
PLUGINS_FOUND=false
for path in "${VLC_PLUGIN_PATHS[@]}"; do
    if [ -d "$path" ]; then
        echo "[INFO] Found VLC plugins at: $path"
        mkdir -p "$BUNDLE_DIR/vlc"
        # Use -L to dereference symlinks when copying
        cp -Lav "$path" "$BUNDLE_DIR/vlc/"
        PLUGINS_FOUND=true
        break
    fi
done

if [ "$PLUGINS_FOUND" = false ]; then
    echo "[WARNING] VLC plugins not found - video/audio codecs may not work!"
fi

# Also copy required dependencies (optional but recommended)
echo "[INFO] Checking for additional dependencies..."

# These are commonly needed by VLC
DEPS=(
    "libavcodec.so.*"
    "libavformat.so.*"
    "libavutil.so.*"
    "libswscale.so.*"
    "libswresample.so.*"
)

# Note: We don't bundle FFmpeg libs by default as they're usually system deps
# Uncomment below if you want a fully self-contained bundle:
# for dep in "${DEPS[@]}"; do
#     for path in "${VLC_LIB_PATHS[@]}"; do
#         if ls "$path"/$dep 1>/dev/null 2>&1; then
#             cp -av "$path"/$dep "$BUNDLE_DIR/" 2>/dev/null || true
#             break
#         fi
#     done
# done

echo ""
echo "====================================="
echo "✅ libVLC bundle prepared!"
echo "====================================="
echo ""
echo "Bundle location: $BUNDLE_DIR"
echo ""
echo "Contents:"
ls -la "$BUNDLE_DIR"
echo ""
if [ -d "$BUNDLE_DIR/vlc/plugins" ]; then
    echo "Plugins size: $(du -sh "$BUNDLE_DIR/vlc/plugins" | cut -f1)"
fi
echo ""
echo "Total bundle size: $(du -sh "$BUNDLE_DIR" | cut -f1)"
