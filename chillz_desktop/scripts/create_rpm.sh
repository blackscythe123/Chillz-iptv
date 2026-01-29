#!/bin/bash
# Create .rpm package for Chillz Desktop
# For Fedora, CentOS, RHEL, openSUSE, and derivatives
#
# Can use either rpmbuild (native) or fpm (Ruby gem)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="chillz-desktop"
APP_DISPLAY_NAME="Chillz Desktop"
APP_EXEC="Chillz_desktop"
VERSION="1.0.0"
RELEASE="1"
ARCH="x86_64"
SUMMARY="Modern IPTV Player powered by VLC"
LICENSE="MIT"
URL="https://github.com/your-repo/chillz-desktop"
BUILD_DIR="build/linux/x64/release/bundle"

echo "======================================="
echo "Creating .rpm package for Chillz Desktop"
echo "======================================="

# Check if build exists
if [ ! -d "$BUILD_DIR" ]; then
    echo "[ERROR] Build not found. Run './build-linux.sh --bundle-vlc' first"
    exit 1
fi

# Create output directory
mkdir -p "$PROJECT_DIR/dist"

# Try fpm first (easier), fall back to rpmbuild
use_fpm() {
    echo "[INFO] Using fpm to create RPM..."
    
    # Create staging directory
    STAGING="$PROJECT_DIR/rpm_staging"
    rm -rf "$STAGING"
    mkdir -p "$STAGING/opt/$APP_NAME"
    mkdir -p "$STAGING/usr/bin"
    mkdir -p "$STAGING/usr/share/applications"
    mkdir -p "$STAGING/usr/share/icons/hicolor/256x256/apps"
    
    # Copy files
    cp -r "$BUILD_DIR"/* "$STAGING/opt/$APP_NAME/"
    
    # Copy icon
    if [ -f "assets/images/app_icon.png" ]; then
        cp "assets/images/app_icon.png" "$STAGING/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png"
    fi
    
    # Create launcher script
    cat > "$STAGING/usr/bin/$APP_NAME" << EOF
#!/bin/bash
export LD_LIBRARY_PATH="/opt/$APP_NAME/lib:\$LD_LIBRARY_PATH"
export VLC_PLUGIN_PATH="/opt/$APP_NAME/lib/vlc/plugins"
cd /opt/$APP_NAME
exec /opt/$APP_NAME/$APP_EXEC "\$@"
EOF
    chmod +x "$STAGING/usr/bin/$APP_NAME"
    
    # Create desktop entry
    cat > "$STAGING/usr/share/applications/$APP_NAME.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$APP_DISPLAY_NAME
GenericName=IPTV Player
Comment=$SUMMARY
Exec=$APP_NAME
Icon=$APP_NAME
Categories=AudioVideo;Video;Player;TV;
Keywords=iptv;tv;video;stream;vlc;
Terminal=false
StartupWMClass=$APP_EXEC
EOF
    
    # Create post-install script
    cat > "$STAGING/post-install.sh" << 'EOF'
#!/bin/bash
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
ldconfig 2>/dev/null || true
EOF
    
    # Build with fpm
    cd "$PROJECT_DIR/dist"
    fpm -s dir -t rpm \
        -n "$APP_NAME" \
        -v "$VERSION" \
        --iteration "$RELEASE" \
        -a "$ARCH" \
        --license "$LICENSE" \
        --description "$SUMMARY" \
        --url "$URL" \
        --vendor "Chillz Team" \
        --maintainer "Chillz Team <team@chillz.app>" \
        --category "AudioVideo" \
        --depends "gtk3 >= 3.22" \
        --depends "alsa-lib" \
        --depends "pulseaudio-libs" \
        --after-install "$STAGING/post-install.sh" \
        -C "$STAGING" \
        opt usr
    
    rm -rf "$STAGING"
    return 0
}

use_rpmbuild() {
    echo "[INFO] Using rpmbuild to create RPM..."
    
    # Setup RPM build directories
    RPM_BUILD_ROOT="$PROJECT_DIR/rpmbuild"
    rm -rf "$RPM_BUILD_ROOT"
    mkdir -p "$RPM_BUILD_ROOT"/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}
    
    # Create source tarball
    TARBALL_NAME="$APP_NAME-$VERSION"
    TARBALL_DIR="$RPM_BUILD_ROOT/SOURCES/$TARBALL_NAME"
    mkdir -p "$TARBALL_DIR/opt/$APP_NAME"
    mkdir -p "$TARBALL_DIR/usr/bin"
    mkdir -p "$TARBALL_DIR/usr/share/applications"
    mkdir -p "$TARBALL_DIR/usr/share/icons/hicolor/256x256/apps"
    
    # Copy files
    cp -r "$BUILD_DIR"/* "$TARBALL_DIR/opt/$APP_NAME/"
    
    # Copy icon
    if [ -f "assets/images/app_icon.png" ]; then
        cp "assets/images/app_icon.png" "$TARBALL_DIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png"
    fi
    
    # Create launcher script
    cat > "$TARBALL_DIR/usr/bin/$APP_NAME" << EOF
#!/bin/bash
export LD_LIBRARY_PATH="/opt/$APP_NAME/lib:\$LD_LIBRARY_PATH"
export VLC_PLUGIN_PATH="/opt/$APP_NAME/lib/vlc/plugins"
cd /opt/$APP_NAME
exec /opt/$APP_NAME/$APP_EXEC "\$@"
EOF
    chmod +x "$TARBALL_DIR/usr/bin/$APP_NAME"
    
    # Create desktop entry
    cat > "$TARBALL_DIR/usr/share/applications/$APP_NAME.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$APP_DISPLAY_NAME
GenericName=IPTV Player
Comment=$SUMMARY
Exec=$APP_NAME
Icon=$APP_NAME
Categories=AudioVideo;Video;Player;TV;
Keywords=iptv;tv;video;stream;vlc;
Terminal=false
StartupWMClass=$APP_EXEC
EOF
    
    # Create tarball
    cd "$RPM_BUILD_ROOT/SOURCES"
    tar -czf "$TARBALL_NAME.tar.gz" "$TARBALL_NAME"
    rm -rf "$TARBALL_NAME"
    
    # Create spec file
    cat > "$RPM_BUILD_ROOT/SPECS/$APP_NAME.spec" << EOF
Name:           $APP_NAME
Version:        $VERSION
Release:        $RELEASE%{?dist}
Summary:        $SUMMARY
License:        $LICENSE
URL:            $URL
Source0:        %{name}-%{version}.tar.gz

# Disable automatic dependency detection (we bundle our own libs)
AutoReqProv:    no

Requires:       gtk3 >= 3.22
Requires:       alsa-lib
Requires:       pulseaudio-libs

%description
Chillz Desktop is a modern IPTV player built with Flutter and libVLC.
It supports various streaming protocols including HLS, RTMP, and more.

Features:
- High-quality video playback powered by VLC
- Support for multiple streaming formats
- Audio track selection
- Keyboard shortcuts
- Modern Flutter-based interface

This package includes all necessary VLC libraries and is fully self-contained.

%prep
%setup -q

%install
mkdir -p %{buildroot}/opt/%{name}
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps

cp -r opt/%{name}/* %{buildroot}/opt/%{name}/
cp usr/bin/%{name} %{buildroot}/usr/bin/
cp usr/share/applications/%{name}.desktop %{buildroot}/usr/share/applications/
if [ -f usr/share/icons/hicolor/256x256/apps/%{name}.png ]; then
    cp usr/share/icons/hicolor/256x256/apps/%{name}.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/
fi

%post
update-desktop-database /usr/share/applications &> /dev/null || :
gtk-update-icon-cache /usr/share/icons/hicolor &> /dev/null || :
ldconfig &> /dev/null || :

%postun
update-desktop-database /usr/share/applications &> /dev/null || :
gtk-update-icon-cache /usr/share/icons/hicolor &> /dev/null || :

%files
%attr(755,root,root) /opt/%{name}/%{name}
/opt/%{name}/data
/opt/%{name}/lib
%attr(755,root,root) /usr/bin/%{name}
/usr/share/applications/%{name}.desktop
/usr/share/icons/hicolor/256x256/apps/%{name}.png

%changelog
* $(date "+%a %b %d %Y") Chillz Team <team@chillz.app> - $VERSION-$RELEASE
- Initial package release
EOF
    
    # Build RPM
    rpmbuild --define "_topdir $RPM_BUILD_ROOT" -bb "$RPM_BUILD_ROOT/SPECS/$APP_NAME.spec"
    
    # Copy result
    cp "$RPM_BUILD_ROOT/RPMS/$ARCH"/*.rpm "$PROJECT_DIR/dist/"
    
    # Cleanup
    rm -rf "$RPM_BUILD_ROOT"
    return 0
}

# Check which tool is available
if command -v fpm &> /dev/null; then
    use_fpm
elif command -v rpmbuild &> /dev/null; then
    use_rpmbuild
else
    echo ""
    echo "[ERROR] Neither fpm nor rpmbuild found!"
    echo ""
    echo "To install fpm (recommended - easier):"
    echo "  sudo apt install ruby ruby-dev build-essential rpm"
    echo "  sudo gem install fpm"
    echo ""
    echo "To install rpmbuild:"
    echo "  # On Ubuntu/Debian:"
    echo "  sudo apt install rpm"
    echo ""
    echo "  # On Fedora/RHEL:"
    echo "  sudo dnf install rpm-build"
    echo ""
    exit 1
fi

# Find the created RPM
RPM_FILE=$(ls -1 "$PROJECT_DIR/dist"/*.rpm 2>/dev/null | head -1)

if [ -n "$RPM_FILE" ] && [ -f "$RPM_FILE" ]; then
    echo ""
    echo "======================================="
    echo "✅ .rpm package created successfully!"
    echo "======================================="
    echo ""
    echo "Output: $RPM_FILE"
    echo "Size: $(du -h "$RPM_FILE" | cut -f1)"
    echo ""
    echo "To install on Fedora/RHEL/CentOS:"
    echo "  sudo dnf install $RPM_FILE"
    echo ""
    echo "To install on openSUSE:"
    echo "  sudo zypper install $RPM_FILE"
    echo ""
    echo "To uninstall:"
    echo "  sudo dnf remove $APP_NAME"
else
    echo "[ERROR] RPM creation failed"
    exit 1
fi
