#!/bin/bash
# Create .deb package for Chillz Desktop
# For Debian, Ubuntu, and derivatives
#
# The resulting .deb is self-contained with all VLC libraries bundled
# Note: Uses manual archive creation to work around dpkg-deb bugs in WSL

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="chillz-desktop"
APP_DISPLAY_NAME="Chillz Desktop"
APP_EXEC="Chillz_desktop"
VERSION="1.0.0"
ARCH="amd64"
MAINTAINER="Chillz Team <team@chillz.app>"
DESCRIPTION="Modern IPTV Player powered by VLC"
HOMEPAGE="https://github.com/your-repo/chillz-desktop"
BUILD_DIR="build/linux/x64/release/bundle"

echo "====================================="
echo "Creating .deb package for Chillz Desktop"
echo "====================================="

# Check if build exists
if [ ! -d "$BUILD_DIR" ]; then
    echo "[ERROR] Build not found. Run './build-linux.sh --bundle-vlc' first"
    exit 1
fi

# WSL workaround: Use /tmp for proper permissions
if grep -qi microsoft /proc/version 2>/dev/null; then
    echo "[INFO] WSL detected - using /tmp for proper permissions"
    DEB_DIR="/tmp/chillz_deb_package_$$"
    WSL_MODE=true
else
    DEB_DIR="$PROJECT_DIR/deb_package"
    WSL_MODE=false
fi

rm -rf "$DEB_DIR"

# Create directory structure
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/opt/$APP_NAME"
mkdir -p "$DEB_DIR/usr/bin"
mkdir -p "$DEB_DIR/usr/share/applications"
mkdir -p "$DEB_DIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$DEB_DIR/usr/share/doc/$APP_NAME"

# Copy application files
echo "[INFO] Copying application files..."
cp -r "$BUILD_DIR"/* "$DEB_DIR/opt/$APP_NAME/"

# Copy icon
if [ -f "assets/images/app_icon.png" ]; then
    cp "assets/images/app_icon.png" "$DEB_DIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png"
fi

# Create launcher script
cat > "$DEB_DIR/usr/bin/$APP_NAME" << EOF
#!/bin/bash
# Launcher script for Chillz Desktop

export LD_LIBRARY_PATH="/opt/$APP_NAME/lib:\$LD_LIBRARY_PATH"
export VLC_PLUGIN_PATH="/opt/$APP_NAME/lib/vlc/plugins"

cd /opt/$APP_NAME
exec /opt/$APP_NAME/$APP_EXEC "\$@"
EOF
chmod +x "$DEB_DIR/usr/bin/$APP_NAME"

# Create desktop entry
cat > "$DEB_DIR/usr/share/applications/$APP_NAME.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$APP_DISPLAY_NAME
GenericName=IPTV Player
Comment=$DESCRIPTION
Exec=$APP_NAME
Icon=$APP_NAME
Categories=AudioVideo;Video;Player;TV;
Keywords=iptv;tv;video;stream;vlc;player;
Terminal=false
StartupWMClass=$APP_EXEC
MimeType=video/mp4;video/x-matroska;video/webm;application/x-mpegURL;
EOF

# Create copyright file
cat > "$DEB_DIR/usr/share/doc/$APP_NAME/copyright" << EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: $APP_DISPLAY_NAME
Source: $HOMEPAGE

Files: *
Copyright: $(date +%Y) Chillz Team
License: MIT

License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 .
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.

This package includes bundled VLC libraries:
VLC media player is licensed under the GNU LGPL version 2.1 or later.
See https://www.videolan.org/vlc/licensing.html
EOF

# Create changelog
cat > "$DEB_DIR/usr/share/doc/$APP_NAME/changelog" << EOF
$APP_NAME ($VERSION) stable; urgency=medium

  * Initial release
  * IPTV streaming support
  * VLC-powered video playback
  * Audio track selection
  * Keyboard shortcuts

 -- $MAINTAINER  $(date -R)
EOF
gzip -9 -n "$DEB_DIR/usr/share/doc/$APP_NAME/changelog"

# Calculate installed size
INSTALLED_SIZE=$(du -sk "$DEB_DIR" | cut -f1)

# Create control file
cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: $APP_NAME
Version: $VERSION
Section: video
Priority: optional
Architecture: $ARCH
Installed-Size: $INSTALLED_SIZE
Maintainer: $MAINTAINER
Homepage: $HOMEPAGE
Description: $DESCRIPTION
 Chillz Desktop is a modern IPTV player built with Flutter and libVLC.
 It supports various streaming protocols including HLS, RTMP, and more.
 .
 Features:
  - High-quality video playback powered by VLC
  - Support for multiple streaming formats
  - Audio track selection
  - Keyboard shortcuts
  - Modern Flutter-based interface
 .
 This package includes all necessary VLC libraries and is fully self-contained.
Depends: libc6 (>= 2.17), libgtk-3-0 (>= 3.22), libasound2, libpulse0
Recommends: fonts-noto-color-emoji
EOF

# Create postinst script (runs after installation)
cat > "$DEB_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e

# Update desktop database
if command -v update-desktop-database > /dev/null; then
    update-desktop-database -q /usr/share/applications 2>/dev/null || true
fi

# Update icon cache
if command -v gtk-update-icon-cache > /dev/null; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
fi

# Update library cache for bundled libs
ldconfig 2>/dev/null || true

exit 0
EOF
chmod 755 "$DEB_DIR/DEBIAN/postinst"

# Create postrm script (runs after removal)
cat > "$DEB_DIR/DEBIAN/postrm" << 'EOF'
#!/bin/bash
set -e

# Update desktop database
if command -v update-desktop-database > /dev/null; then
    update-desktop-database -q /usr/share/applications 2>/dev/null || true
fi

# Update icon cache
if command -v gtk-update-icon-cache > /dev/null; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
fi

exit 0
EOF
chmod 755 "$DEB_DIR/DEBIAN/postrm"

# Create conffiles (empty - we have no config files in /etc)
touch "$DEB_DIR/DEBIAN/conffiles"

# Set correct permissions
find "$DEB_DIR" -type d -exec chmod 755 {} \;
find "$DEB_DIR/opt" -type f -exec chmod 644 {} \;
chmod 755 "$DEB_DIR/opt/$APP_NAME/$APP_EXEC"
chmod 755 "$DEB_DIR/usr/bin/$APP_NAME"
find "$DEB_DIR/opt/$APP_NAME/lib" -name "*.so*" -exec chmod 755 {} \; 2>/dev/null || true

echo "[INFO] Building .deb package..."

# Create output directory
mkdir -p "$PROJECT_DIR/dist"

DEB_FILE="$PROJECT_DIR/dist/${APP_NAME}_${VERSION}_${ARCH}.deb"

# Build using manual archive creation (works around dpkg-deb bugs in WSL)
build_deb_manually() {
    local BUILD_TMP="/tmp/deb_build_$$"
    rm -rf "$BUILD_TMP"
    mkdir -p "$BUILD_TMP"
    
    echo "[INFO] Creating debian-binary..."
    echo "2.0" > "$BUILD_TMP/debian-binary"
    
    echo "[INFO] Creating control.tar.xz..."
    tar -cJf "$BUILD_TMP/control.tar.xz" -C "$DEB_DIR/DEBIAN" .
    
    echo "[INFO] Creating data.tar.xz (this may take a moment)..."
    cd "$DEB_DIR"
    tar --exclude='./DEBIAN' -cJf "$BUILD_TMP/data.tar.xz" .
    
    echo "[INFO] Creating final .deb archive..."
    cd "$BUILD_TMP"
    ar rcs "$DEB_FILE" debian-binary control.tar.xz data.tar.xz
    
    rm -rf "$BUILD_TMP"
}

# Try dpkg-deb first, fall back to manual build
dpkg-deb --build --root-owner-group "$DEB_DIR" "$DEB_FILE" 2>/dev/null && \
    [ $(stat -c%s "$DEB_FILE" 2>/dev/null || echo 0) -gt 10000 ] || {
    echo "[INFO] dpkg-deb failed or produced invalid package, using manual build..."
    build_deb_manually
}

# Verify the package
echo ""
echo "[INFO] Package contents:"
dpkg-deb --contents "$DEB_FILE" | head -30
echo "... (truncated)"

echo ""
echo "[INFO] Package info:"
dpkg-deb --info "$DEB_FILE"

# Cleanup
rm -rf "$DEB_DIR"

echo ""
echo "======================================="
echo "✅ .deb package created successfully!"
echo "======================================="
echo ""
echo "Output: $DEB_FILE"
echo "Size: $(du -h "$DEB_FILE" | cut -f1)"
echo ""
echo "To install:"
echo "  sudo dpkg -i $DEB_FILE"
echo "  # or"
echo "  sudo apt install ./$DEB_FILE"
echo ""
echo "To uninstall:"
echo "  sudo apt remove $APP_NAME"
