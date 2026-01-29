# Linux Build Instructions for Chillz Desktop

This document explains how to build Chillz Desktop for Linux with bundled libVLC.

## Prerequisites

1. **Flutter SDK** installed and configured for Linux desktop
2. **Build essentials**: `sudo apt install build-essential cmake pkg-config`
3. **GTK development files**: `sudo apt install libgtk-3-dev`
4. **VLC and development files**: `sudo apt install vlc libvlc-dev`

## Quick Start - Build All Packages

```bash
cd chillz_desktop

# Make all scripts executable
chmod +x build-linux.sh create-linux-package.sh scripts/*.sh

# Build all packages (tarball, AppImage, .deb, .rpm)
./scripts/build-all-packages.sh
```

This creates self-contained packages in the `dist/` directory.

## Quick Build

### Option 1: Build with System VLC (simpler, smaller package)

```bash
cd chillz_desktop

# Make scripts executable
chmod +x build-linux.sh create-linux-package.sh scripts/*.sh

# Build the app
./build-linux.sh
```

The app will be in: `build/linux/x64/release/bundle/`

### Option 2: Build with Bundled VLC (self-contained, recommended for distribution)

```bash
cd chillz_desktop

# Make scripts executable  
chmod +x build-linux.sh create-linux-package.sh scripts/*.sh

# Prepare the VLC bundle (run once)
./scripts/prepare_libvlc_bundle.sh

# Build with bundled VLC
./build-linux.sh --bundle-vlc
```

## Creating Distribution Packages

### All Packages at Once

```bash
./scripts/build-all-packages.sh
```

This creates all available formats in `dist/`:
- `Chillz_desktop-1.0.0-linux-x86_64.tar.gz` (portable tarball)
- `Chillz_desktop-1.0.0-x86_64.AppImage` (universal Linux)
- `chillz-desktop_1.0.0_amd64.deb` (Debian/Ubuntu)
- `chillz-desktop-1.0.0-1.x86_64.rpm` (Fedora/RHEL)

### Individual Packages

```bash
# Tarball only
./scripts/build-all-packages.sh tarball

# AppImage only
./scripts/build-all-packages.sh appimage

# Debian package only
./scripts/build-all-packages.sh deb

# RPM package only
./scripts/build-all-packages.sh rpm

# Skip rebuilding (if already built)
./scripts/build-all-packages.sh --quick deb rpm
```

## Installation

### Portable Tarball
```bash
tar -xzf Chillz_desktop-1.0.0-linux-x86_64.tar.gz
cd bundle
./run.sh  # or: ./Chillz_desktop
```

### AppImage (Universal)
```bash
chmod +x Chillz_desktop-1.0.0-x86_64.AppImage
./Chillz_desktop-1.0.0-x86_64.AppImage
```

### Debian/Ubuntu (.deb)
```bash
sudo apt install ./chillz-desktop_1.0.0_amd64.deb
chillz-desktop
```

### Fedora/RHEL (.rpm)
```bash
sudo dnf install ./chillz-desktop-1.0.0-1.x86_64.rpm
chillz-desktop
```

### openSUSE
```bash
sudo zypper install ./chillz-desktop-1.0.0-1.x86_64.rpm
chillz-desktop
```

## Manual Build Steps

If the scripts don't work, you can build manually:

```bash
# 1. Build Flutter app
flutter build linux --release

# 2. Copy VLC libraries (if bundling)
BUILD_DIR="build/linux/x64/release/bundle"
mkdir -p "$BUILD_DIR/lib/vlc"

# Copy libvlc
cp /usr/lib/x86_64-linux-gnu/libvlc.so* "$BUILD_DIR/lib/"
cp /usr/lib/x86_64-linux-gnu/libvlccore.so* "$BUILD_DIR/lib/"

# Copy VLC plugins
cp -r /usr/lib/x86_64-linux-gnu/vlc/plugins "$BUILD_DIR/lib/vlc/"
```

## Running the App

```bash
cd build/linux/x64/release/bundle

# If using bundled VLC:
export LD_LIBRARY_PATH="$PWD/lib:$LD_LIBRARY_PATH"
export VLC_PLUGIN_PATH="$PWD/lib/vlc/plugins"

./Chillz_desktop
```

## Troubleshooting

### "libvlc.so not found"
Install VLC: `sudo apt install vlc libvlc-dev`

### Build errors with GTK
Install GTK dev files: `sudo apt install libgtk-3-dev`

### Video doesn't play
- Make sure VLC plugins are bundled or VLC is installed
- Check: `ls build/linux/x64/release/bundle/lib/vlc/plugins/`

### Plugin path errors
Set the VLC_PLUGIN_PATH environment variable before running:
```bash
export VLC_PLUGIN_PATH="/path/to/app/lib/vlc/plugins"
```

## Architecture

The Linux build uses:
- **vlc_player_plugin.cc**: Native C code that interfaces with libVLC
- **vlc_player_service.dart**: Dart wrapper using platform channels
- **CMakeLists.txt**: Build configuration that bundles VLC libraries

The app dynamically loads libVLC at runtime, first trying bundled libraries, then falling back to system VLC.
