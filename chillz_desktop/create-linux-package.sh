#!/bin/bash
# Create a distributable Linux package for Chillz Desktop
# Creates a self-contained tarball with all dependencies
#
# Usage: ./create-linux-package.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Chillz_desktop"
VERSION="1.0.0"
ARCH="x86_64"
BUILD_DIR="build/linux/x64/release/bundle"
PACKAGE_NAME="${APP_NAME}-${VERSION}-linux-${ARCH}"
DIST_DIR="dist"

echo "====================================="
echo "Creating Linux Distribution Package"
echo "====================================="

# Check if build exists
if [ ! -d "$BUILD_DIR" ]; then
    echo "[ERROR] Build not found at: $BUILD_DIR"
    echo "[INFO] Run './build-linux.sh --bundle-vlc' first"
    exit 1
fi

# Create dist directory
mkdir -p "$DIST_DIR"
rm -rf "$DIST_DIR/$PACKAGE_NAME"
mkdir -p "$DIST_DIR/$PACKAGE_NAME"

echo "[INFO] Copying application files..."

# Copy entire bundle
cp -av "$BUILD_DIR"/* "$DIST_DIR/$PACKAGE_NAME/"

# Create launcher script
cat > "$DIST_DIR/$PACKAGE_NAME/run.sh" << 'EOF'
#!/bin/bash
# Launcher script for Chillz Desktop
# This sets up the environment for bundled libraries

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Add bundled libraries to library path
export LD_LIBRARY_PATH="$SCRIPT_DIR/lib:$LD_LIBRARY_PATH"

# Set VLC plugin path if bundled
if [ -d "$SCRIPT_DIR/lib/vlc/plugins" ]; then
    export VLC_PLUGIN_PATH="$SCRIPT_DIR/lib/vlc/plugins"
fi

# Run the application
exec "$SCRIPT_DIR/Chillz_desktop" "$@"
EOF
chmod +x "$DIST_DIR/$PACKAGE_NAME/run.sh"

# Create .desktop file for Linux desktop integration
cat > "$DIST_DIR/$PACKAGE_NAME/chillz-desktop.desktop" << EOF
[Desktop Entry]
Name=Chillz TV
Comment=IPTV Player
Exec=Chillz_desktop
Icon=chillz
Type=Application
Categories=AudioVideo;Video;Player;
Terminal=false
StartupWMClass=Chillz_desktop
EOF

# Create README
cat > "$DIST_DIR/$PACKAGE_NAME/README.txt" << EOF
Chillz Desktop - IPTV Player for Linux
======================================

Version: $VERSION

INSTALLATION:
-------------
1. Extract this archive to your desired location
2. Run the application using: ./run.sh

REQUIREMENTS:
-------------
- GTK 3.0 (usually pre-installed on most Linux distributions)
- X11 or Wayland display server

If using system VLC (not bundled):
- VLC media player: sudo apt install vlc

TROUBLESHOOTING:
----------------
If the application doesn't start:
1. Make sure the run.sh script is executable: chmod +x run.sh
2. Check if GTK is installed: apt list --installed | grep gtk
3. Try running from terminal to see error messages: ./run.sh

For issues with video playback:
1. Make sure VLC is installed or bundled libraries are present in lib/
2. Check VLC plugin path: ls lib/vlc/plugins/

SUPPORT:
--------
https://github.com/your-repo/chillz-desktop

EOF

echo "[INFO] Creating tarball..."
cd "$DIST_DIR"
tar -czvf "${PACKAGE_NAME}.tar.gz" "$PACKAGE_NAME"

echo ""
echo "====================================="
echo "✅ Package created successfully!"
echo "====================================="
echo ""
echo "Package: $DIST_DIR/${PACKAGE_NAME}.tar.gz"
echo "Size: $(du -h "${PACKAGE_NAME}.tar.gz" | cut -f1)"
echo ""
echo "To distribute:"
echo "  1. Share the .tar.gz file"
echo "  2. Users extract and run: ./run.sh"
