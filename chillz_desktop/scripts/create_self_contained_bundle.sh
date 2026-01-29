#!/bin/bash
# Complete self-contained Linux bundle builder
# This script creates a fully portable bundle with ALL dependencies
# including VLC libraries, plugins, and codec dependencies

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="Chillz_desktop"
VERSION="1.0.0"
BUNDLE_DIR="$PROJECT_DIR/libvlc_bundle_linux"

echo "====================================="
echo "Creating Self-Contained VLC Bundle"
echo "====================================="

# Clean existing bundle
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/vlc"

# Common library paths
LIB_PATHS=(
    "/usr/lib/x86_64-linux-gnu"
    "/usr/lib64"
    "/usr/lib"
    "/lib/x86_64-linux-gnu"
    "/lib64"
)

# Function to find and copy a library
copy_lib() {
    local lib_name="$1"
    local found=false
    
    for path in "${LIB_PATHS[@]}"; do
        # Try exact match first
        if [ -f "$path/$lib_name" ]; then
            cp -Lv "$path/$lib_name" "$BUNDLE_DIR/" 2>/dev/null || true
            found=true
            break
        fi
        # Try with wildcard for versioned libs
        for file in "$path"/$lib_name*; do
            if [ -f "$file" ]; then
                cp -Lv "$file" "$BUNDLE_DIR/" 2>/dev/null || true
                found=true
            fi
        done
        if [ "$found" = true ]; then break; fi
    done
    
    if [ "$found" = false ]; then
        echo "[WARN] Library not found: $lib_name"
    fi
}

echo ""
echo "[INFO] Copying VLC core libraries..."

# Core VLC libraries
copy_lib "libvlc.so"
copy_lib "libvlccore.so"

echo ""
echo "[INFO] Copying VLC plugins..."

# Find and copy VLC plugins
VLC_PLUGIN_PATHS=(
    "/usr/lib/x86_64-linux-gnu/vlc/plugins"
    "/usr/lib64/vlc/plugins"
    "/usr/lib/vlc/plugins"
)

for plugin_path in "${VLC_PLUGIN_PATHS[@]}"; do
    if [ -d "$plugin_path" ] && [ "$(ls -A $plugin_path 2>/dev/null)" ]; then
        echo "[INFO] Found plugins at: $plugin_path"
        cp -Lr "$plugin_path" "$BUNDLE_DIR/vlc/"
        break
    fi
done

# If plugins directory is empty, try to find individual plugin .so files
if [ ! -d "$BUNDLE_DIR/vlc/plugins" ] || [ -z "$(ls -A $BUNDLE_DIR/vlc/plugins 2>/dev/null)" ]; then
    echo "[INFO] Looking for VLC plugin directories..."
    mkdir -p "$BUNDLE_DIR/vlc/plugins"
    
    # Plugin categories to look for
    PLUGIN_CATEGORIES=(
        "access" "audio_filter" "audio_mixer" "audio_output"
        "codec" "demux" "lua" "meta_engine" "misc"
        "packetizer" "services_discovery" "spu" "stream_filter"
        "stream_out" "text_renderer" "video_chroma" "video_filter"
        "video_output" "video_splitter" "visualization"
    )
    
    for cat in "${PLUGIN_CATEGORIES[@]}"; do
        for base_path in "${VLC_PLUGIN_PATHS[@]}"; do
            if [ -d "$base_path/$cat" ]; then
                mkdir -p "$BUNDLE_DIR/vlc/plugins/$cat"
                cp -Lr "$base_path/$cat"/* "$BUNDLE_DIR/vlc/plugins/$cat/" 2>/dev/null || true
            fi
        done
    done
fi

echo ""
echo "[INFO] Copying codec and dependency libraries..."

# Essential codec libraries (FFmpeg/libav)
CODEC_LIBS=(
    "libavcodec.so"
    "libavformat.so"
    "libavutil.so"
    "libswscale.so"
    "libswresample.so"
    "libpostproc.so"
    "libavfilter.so"
    "libavdevice.so"
)

for lib in "${CODEC_LIBS[@]}"; do
    copy_lib "$lib"
done

# Additional multimedia libraries VLC might need
EXTRA_LIBS=(
    # Audio
    "libpulse.so"
    "libasound.so"
    "libopenal.so"
    "libsndfile.so"
    "libFLAC.so"
    "libvorbis.so"
    "libvorbisenc.so"
    "libogg.so"
    "libopus.so"
    "libmp3lame.so"
    "libmpg123.so"
    # Video
    "libx264.so"
    "libx265.so"
    "libvpx.so"
    "libtheora.so"
    "libdav1d.so"
    "libaom.so"
    # Streaming
    "librtmp.so"
    "libsrt.so"
    # Image
    "libpng16.so"
    "libjpeg.so"
    "libwebp.so"
    # Text/Fonts
    "libfreetype.so"
    "libfontconfig.so"
    "libfribidi.so"
    "libharfbuzz.so"
    # Network/Security
    "libssl.so"
    "libcrypto.so"
    "libgnutls.so"
    # XML
    "libxml2.so"
    # Compression
    "liblzma.so"
    "libz.so"
    "libbz2.so"
)

for lib in "${EXTRA_LIBS[@]}"; do
    copy_lib "$lib"
done

echo ""
echo "[INFO] Creating library symlinks..."

# Create necessary symlinks
cd "$BUNDLE_DIR"
for lib in *.so.*.*; do
    if [ -f "$lib" ]; then
        # Get base name (e.g., libvlc.so.5.6.0 -> libvlc.so.5 and libvlc.so)
        base="${lib%.*.*}"  # libvlc.so.5
        short="${lib%%.*}.so"  # libvlc.so
        
        if [ ! -e "$base" ] && [ "$base" != "$lib" ]; then
            ln -sf "$lib" "$base" 2>/dev/null || true
        fi
        if [ ! -e "$short" ] && [ "$short" != "$lib" ]; then
            ln -sf "$lib" "$short" 2>/dev/null || true
        fi
    fi
done
cd "$PROJECT_DIR"

echo ""
echo "[INFO] Setting permissions..."
chmod -R 755 "$BUNDLE_DIR"

echo ""
echo "====================================="
echo "✅ Self-contained VLC bundle created!"
echo "====================================="
echo ""
echo "Bundle location: $BUNDLE_DIR"
echo "Total size: $(du -sh "$BUNDLE_DIR" | cut -f1)"
echo ""
ls -la "$BUNDLE_DIR"/*.so* 2>/dev/null | head -20 || echo "(no libraries found)"
echo ""
if [ -d "$BUNDLE_DIR/vlc/plugins" ]; then
    echo "Plugins: $(find "$BUNDLE_DIR/vlc/plugins" -name "*.so" 2>/dev/null | wc -l) files"
fi
