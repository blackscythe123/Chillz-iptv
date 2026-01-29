#!/bin/bash
# Bundle libVLC libraries for Linux distribution
# This copies libVLC and its plugins to the Flutter build output
#
# Usage:
#   ./bundle_libvlc_linux.sh                      # Use system VLC
#   ./bundle_libvlc_linux.sh --source /path/to/vlc  # Use custom VLC path

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default paths
SOURCE_PATH=""
BUILD_OUTPUT="$PROJECT_DIR/build/linux/x64/release/bundle"
LIB_DIR="$BUILD_OUTPUT/lib"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --source)
            SOURCE_PATH="$2"
            shift 2
            ;;
        --output)
            BUILD_OUTPUT="$2"
            LIB_DIR="$BUILD_OUTPUT/lib"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

echo "[INFO] Bundling libVLC for Linux..."

# Check if build output exists
if [ ! -d "$BUILD_OUTPUT" ]; then
    echo "[ERROR] Build output not found at: $BUILD_OUTPUT"
    echo "[INFO] Run 'flutter build linux --release' first"
    exit 1
fi

# Create lib directory if it doesn't exist
mkdir -p "$LIB_DIR"

# Function to copy VLC files from a source
copy_vlc_files() {
    local src="$1"
    
    echo "[INFO] Copying libVLC from: $src"
    
    # Copy main libraries
    for lib in libvlc.so* libvlccore.so*; do
        if [ -f "$src/$lib" ]; then
            cp -av "$src/$lib" "$LIB_DIR/"
        fi
    done
    
    # Copy plugins directory
    if [ -d "$src/vlc/plugins" ]; then
        echo "[INFO] Copying VLC plugins..."
        mkdir -p "$LIB_DIR/vlc"
        cp -av "$src/vlc/plugins" "$LIB_DIR/vlc/"
    elif [ -d "$src/plugins" ]; then
        echo "[INFO] Copying VLC plugins..."
        mkdir -p "$LIB_DIR/vlc"
        cp -av "$src/plugins" "$LIB_DIR/vlc/"
    fi
}

# If source path provided, use it
if [ -n "$SOURCE_PATH" ]; then
    if [ ! -d "$SOURCE_PATH" ]; then
        echo "[ERROR] Source path not found: $SOURCE_PATH"
        exit 1
    fi
    copy_vlc_files "$SOURCE_PATH"
else
    # Try to find system VLC
    echo "[INFO] Looking for system VLC installation..."
    
    # Common VLC library locations
    VLC_PATHS=(
        "/usr/lib/x86_64-linux-gnu"
        "/usr/lib64"
        "/usr/lib"
        "/usr/local/lib"
    )
    
    VLC_FOUND=false
    for path in "${VLC_PATHS[@]}"; do
        if [ -f "$path/libvlc.so.5" ]; then
            echo "[INFO] Found libVLC at: $path"
            
            # Copy main libraries
            cp -av "$path"/libvlc.so* "$LIB_DIR/" 2>/dev/null || true
            cp -av "$path"/libvlccore.so* "$LIB_DIR/" 2>/dev/null || true
            
            # Find and copy plugins
            for plugin_path in "/usr/lib/x86_64-linux-gnu/vlc/plugins" "/usr/lib64/vlc/plugins" "/usr/lib/vlc/plugins"; do
                if [ -d "$plugin_path" ]; then
                    echo "[INFO] Copying VLC plugins from: $plugin_path"
                    mkdir -p "$LIB_DIR/vlc"
                    cp -av "$plugin_path" "$LIB_DIR/vlc/"
                    break
                fi
            done
            
            VLC_FOUND=true
            break
        fi
    done
    
    if [ "$VLC_FOUND" = false ]; then
        echo "[ERROR] libVLC not found on system"
        echo "[INFO] Install VLC with: sudo apt install vlc libvlc-dev"
        exit 1
    fi
fi

# Create plugins cache (needed by VLC)
if [ -d "$LIB_DIR/vlc/plugins" ]; then
    echo "[INFO] Creating VLC plugins cache..."
    # VLC will create this on first run, but we can pre-create the directory
    mkdir -p "$LIB_DIR/vlc/plugins/cache"
fi

# Set proper permissions
chmod -R 755 "$LIB_DIR"

echo ""
echo "[INFO] ====================================="
echo "[INFO] libVLC bundled successfully!"
echo "[INFO] ====================================="
echo "[INFO] Libraries copied to: $LIB_DIR"
echo ""

# List what was copied
echo "[INFO] Bundled files:"
ls -la "$LIB_DIR"/libvlc* 2>/dev/null || echo "  (no libvlc files)"
if [ -d "$LIB_DIR/vlc/plugins" ]; then
    echo "[INFO] VLC plugins directory: $(du -sh "$LIB_DIR/vlc/plugins" | cut -f1)"
fi
