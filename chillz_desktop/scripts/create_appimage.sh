#!/bin/bash
# Create AppImage for Chillz Desktop
# AppImage is a portable format that runs on most Linux distributions
#
# Requirements: 
#   - appimagetool (will be downloaded if not present)
#   - fuse (for running AppImages)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="Chillz_desktop"
APP_ID="com.chillz.desktop"
VERSION="1.0.0"
ARCH="x86_64"
BUILD_DIR="build/linux/x64/release/bundle"
APPDIR="$PROJECT_DIR/AppDir"
TOOLS_DIR="$PROJECT_DIR/tools"

echo "====================================="
echo "Creating AppImage for Chillz Desktop"
echo "====================================="

# Check if build exists
if [ ! -d "$BUILD_DIR" ]; then
    echo "[ERROR] Build not found. Run './build-linux.sh --bundle-vlc' first"
    exit 1
fi

# Download appimagetool if not present
mkdir -p "$TOOLS_DIR"
APPIMAGETOOL="$TOOLS_DIR/appimagetool-x86_64.AppImage"
if [ ! -f "$APPIMAGETOOL" ]; then
    echo "[INFO] Downloading appimagetool..."
    wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" \
        -O "$APPIMAGETOOL" || {
        echo "[ERROR] Failed to download appimagetool"
        echo "[INFO] You can manually download from: https://github.com/AppImage/AppImageKit/releases"
        exit 1
    }
    chmod +x "$APPIMAGETOOL"
fi

echo "[INFO] Preparing AppDir structure..."

# Clean and create AppDir
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR/usr/share/metainfo"

# Copy application
echo "[INFO] Copying application files..."
cp "$BUILD_DIR/$APP_NAME" "$APPDIR/usr/bin/"
cp -r "$BUILD_DIR/data" "$APPDIR/usr/bin/"
cp -r "$BUILD_DIR/lib"/* "$APPDIR/usr/lib/"

# Copy icon
if [ -f "assets/images/app_icon.png" ]; then
    cp "assets/images/app_icon.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/chillz.png"
    cp "assets/images/app_icon.png" "$APPDIR/chillz.png"
else
    # Create a placeholder icon
    echo "[WARN] No icon found, creating placeholder"
    convert -size 256x256 xc:cyan "$APPDIR/chillz.png" 2>/dev/null || \
        touch "$APPDIR/chillz.png"
fi

# Create desktop file
cat > "$APPDIR/usr/share/applications/chillz-desktop.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Chillz TV
GenericName=IPTV Player
Comment=Modern IPTV Player with VLC backend
Exec=Chillz_desktop
Icon=chillz
Categories=AudioVideo;Video;Player;TV;
Keywords=iptv;tv;video;stream;vlc;
Terminal=false
StartupWMClass=Chillz_desktop
EOF

# Copy desktop file to AppDir root (required by AppImage)
cp "$APPDIR/usr/share/applications/chillz-desktop.desktop" "$APPDIR/chillz-desktop.desktop"

# Create AppStream metadata
cat > "$APPDIR/usr/share/metainfo/$APP_ID.appdata.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>$APP_ID</id>
  <name>Chillz TV</name>
  <summary>Modern IPTV Player</summary>
  <metadata_license>MIT</metadata_license>
  <project_license>MIT</project_license>
  <description>
    <p>Chillz Desktop is a modern IPTV player built with Flutter and libVLC.</p>
    <p>Features:</p>
    <ul>
      <li>High-quality video playback powered by VLC</li>
      <li>Support for HLS, RTMP, and other streaming formats</li>
      <li>Audio track selection</li>
      <li>Keyboard shortcuts</li>
      <li>Beautiful modern interface</li>
    </ul>
  </description>
  <launchable type="desktop-id">chillz-desktop.desktop</launchable>
  <url type="homepage">https://github.com/your-repo/chillz-desktop</url>
  <screenshots>
    <screenshot type="default">
      <caption>Main player interface</caption>
    </screenshot>
  </screenshots>
  <releases>
    <release version="$VERSION" date="$(date +%Y-%m-%d)">
      <description>
        <p>Initial release</p>
      </description>
    </release>
  </releases>
  <content_rating type="oars-1.1" />
</component>
EOF

# Create AppRun script
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
# AppRun script for Chillz Desktop AppImage

SELF=$(readlink -f "$0")
HERE=${SELF%/*}

# Set up library paths
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"

# Set up VLC plugin path
export VLC_PLUGIN_PATH="${HERE}/usr/lib/vlc/plugins"

# Set XDG paths
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS}"

# Change to bin directory for relative data paths
cd "${HERE}/usr/bin"

# Run the application
exec "${HERE}/usr/bin/Chillz_desktop" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Create symlink for icon at root
ln -sf usr/share/icons/hicolor/256x256/apps/chillz.png "$APPDIR/.DirIcon" 2>/dev/null || true

echo "[INFO] Building AppImage..."

# Create output directory
mkdir -p "$PROJECT_DIR/dist"

# Build the AppImage
export ARCH=x86_64
"$APPIMAGETOOL" "$APPDIR" "$PROJECT_DIR/dist/${APP_NAME}-${VERSION}-${ARCH}.AppImage" || {
    echo ""
    echo "[WARN] appimagetool failed. This might be because:"
    echo "  1. FUSE is not installed (needed to run .AppImage tools)"
    echo "  2. Running in WSL without FUSE support"
    echo ""
    echo "[INFO] Trying with --appimage-extract-and-run..."
    "$APPIMAGETOOL" --appimage-extract-and-run "$APPDIR" "$PROJECT_DIR/dist/${APP_NAME}-${VERSION}-${ARCH}.AppImage" || {
        echo ""
        echo "[INFO] Alternative: extracting appimagetool and running directly..."
        cd "$TOOLS_DIR"
        ./appimagetool-x86_64.AppImage --appimage-extract 2>/dev/null || true
        if [ -d "squashfs-root" ]; then
            ./squashfs-root/AppRun "$APPDIR" "$PROJECT_DIR/dist/${APP_NAME}-${VERSION}-${ARCH}.AppImage"
        else
            echo "[ERROR] Could not create AppImage. Please run on native Linux with FUSE."
            # Create a tarball as fallback
            echo "[INFO] Creating portable tarball instead..."
            cd "$PROJECT_DIR"
            tar -czvf "dist/${APP_NAME}-${VERSION}-portable-${ARCH}.tar.gz" -C "$(dirname $APPDIR)" "$(basename $APPDIR)"
            echo "Created: dist/${APP_NAME}-${VERSION}-portable-${ARCH}.tar.gz"
            exit 0
        fi
    }
}

# Cleanup
rm -rf "$APPDIR"

echo ""
echo "====================================="
echo "✅ AppImage created successfully!"
echo "====================================="
echo ""
echo "Output: dist/${APP_NAME}-${VERSION}-${ARCH}.AppImage"
echo "Size: $(du -h "$PROJECT_DIR/dist/${APP_NAME}-${VERSION}-${ARCH}.AppImage" 2>/dev/null | cut -f1 || echo "N/A")"
echo ""
echo "To run:"
echo "  chmod +x dist/${APP_NAME}-${VERSION}-${ARCH}.AppImage"
echo "  ./dist/${APP_NAME}-${VERSION}-${ARCH}.AppImage"
