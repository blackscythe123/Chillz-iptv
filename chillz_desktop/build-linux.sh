#!/bin/bash
# Build Chillz Desktop for Linux with bundled libVLC
# Usage: ./build-linux.sh [--bundle-vlc]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "====================================="
echo "Building Chillz Desktop for Linux"
echo "====================================="

# Check if we should bundle VLC
BUNDLE_VLC=false
if [[ "$1" == "--bundle-vlc" ]]; then
    BUNDLE_VLC=true
fi

# Step 1: Build Flutter Linux app
echo ""
echo "Step 1: Building Flutter Linux app..."
flutter build linux --release

if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

# Step 2: Bundle libVLC if requested
if [ "$BUNDLE_VLC" = true ]; then
    echo ""
    echo "Step 2: Bundling libVLC files..."
    
    if [ -d "libvlc_bundle_linux" ] && [ -f "libvlc_bundle_linux/libvlc.so.5" ]; then
        echo "Found local libvlc_bundle_linux — copying to build output..."
        ./scripts/bundle_libvlc_linux.sh --source "$SCRIPT_DIR/libvlc_bundle_linux"
    else
        echo "No local libvlc_bundle_linux found — attempting to bundle from system VLC..."
        ./scripts/bundle_libvlc_linux.sh
    fi
    
    if [ $? -ne 0 ]; then
        echo "LibVLC bundling failed!"
        echo "Make sure VLC is installed: sudo apt install vlc libvlc-dev"
        exit 1
    fi
fi

echo ""
echo "====================================="
echo "✅ Build complete!"
echo "====================================="
echo ""
echo "The app is ready at: build/linux/x64/release/bundle/Chillz_desktop"
echo ""
echo "To run:"
echo "  cd build/linux/x64/release/bundle && ./Chillz_desktop"
echo ""

if [ "$BUNDLE_VLC" = false ]; then
    echo "Note: libVLC was not bundled. Make sure VLC is installed on the target system:"
    echo "  sudo apt install vlc"
    echo ""
    echo "To create a fully self-contained build with bundled VLC:"
    echo "  ./build-linux.sh --bundle-vlc"
fi
