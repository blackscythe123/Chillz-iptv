# Chillz Desktop (Flutter + libVLC) 🎬

**Chillz Desktop** is a native Windows and Linux IPTV player that bridges the gap between high-performance C++ media playback and modern Flutter UI.

It is built to handle the complexities of live HLS streaming that standard video players often fail at, providing a "VLC-grade" experience with a beautiful interface and **zero UI freezing**.

---

## 📦 Downloads

### Version 1.0.0

| Platform | Package | Size | Download |
|----------|---------|------|----------|
| **Linux (Debian/Ubuntu)** | `.deb` | ~6.7 MB | `chillz-desktop_1.0.0_amd64.deb` |
| **Linux (Portable)** | `.tar.gz` | ~18 MB | `Chillz_desktop-1.0.0-linux-x86_64.tar.gz` |
| **Windows** | `.msi` | ~70 MB | Available in releases |

### Installation

**Debian/Ubuntu:**
```bash
sudo apt install ./chillz-desktop_1.0.0_amd64.deb
chillz-desktop
```

**Portable Linux:**
```bash
tar -xzf Chillz_desktop-1.0.0-linux-x86_64.tar.gz
cd Chillz_desktop-1.0.0-linux-x86_64
./run.sh
```

**Windows:**
Run the MSI installer or extract the portable ZIP.

---

## 📦 Supported Platforms

| Platform | Status | Build Script |
|----------|--------|--------------|
| Windows  | ✅ Full Support | `build-with-vlc.bat` |
| Linux    | ✅ Full Support | `build-linux.sh` |
| macOS    | 🔄 Planned | - |

---

## 🏛️ Architecture Deep Dive

This application follows a strict multi-threaded architecture to ensure stability and performance:

### 1. Native Layer (C++) - `windows/runner/vlc_player_plugin.cpp`
This is the core engine. Flutter cannot render video efficiently on its own, so we bypass it.

-   **Direct libVLC Embedding**: We link directly against `libvlc.dll` and `libvlccore.dll`.
-   **VLC Command Thread**: **NEW** - Dedicated worker thread handles ALL blocking VLC operations (stop, play, media creation). The UI thread only enqueues tasks and returns immediately.
-   **Child HWND**: The plugin creates a completely separate Windows HWND (Window Handle) that is a child of the Flutter window.
-   **Direct Rendering**: VLC renders video pixels directly into this child HWND. Use `_updateVideoBounds()` in Flutter to resize this window to match the UI layout.
-   **Event Loop**: A custom `VlcEventCallback` captures low-level libVLC events (Buffering, Errors, EOS) and sends them to Flutter via an `EventChannel`.
-   **Thread Safety**: Events are dispatched via `PostMessage` to ensure they always run on the platform thread.

### 2. Service Layer (Dart) - `lib/services/vlc_player_service.dart`
The bridge between chaos and order.

-   **Singleton Controller**: `VlcPlayerController` manages the single instance of the player.
-   **Platform Channels**:
    -   `MethodChannel`: Sends commands DOWN to C++ (Play, Stop, SetVolume).
    -   `EventChannel`: Receives state updates UP from C++ (Time, State, Errors).
-   **State Management**: Normalizes disjointed VLC states (Opening, Buffering, Playing) into a clean UI state machine.
-   **Non-blocking**: All platform channel calls return immediately; actual work happens on VLC command thread.

### 3. UI Layer (Flutter) - `lib/main.dart`
The user experience.

-   **Z-Ordering Hack**: Since the video is a native HWND, it technically floats *on top* of the Flutter canvas. To show dialogs (like Audio Selection), we use `_vlc.hideVideo()` to temporarily hide the HWND so the Flutter dialog is visible.
-   **Input Handling**: Captures global keyboard shortcuts (Space, F, A, M) even when the video window has OS-level focus.
-   **Consolidated Post-Play Setup**: Single async handler prevents timer bursts and reduces platform channel calls.

---

## ✨ Key Features

-   **Zero UI Freezing**: VLC command thread ensures Windows never shows "Not Responding" state
-   **Audio Track Selection**: Full support for multi-language streams.
    -   *Shortcut*: Press `A` to toggle tracks.
-   **Volume Boost**: VLC-style amplification up to 200%.
-   **Fullscreen Mode**: Press `F` to toggle fullscreen.
-   **Keyboard Shortcuts**: Space (play/pause), M (mute), Arrow keys (volume), R (retry), S (stop).

---

## 🛠️ Development Setup

### Prerequisites

**Windows:**
-   Windows 10/11 x64.
-   Visual Studio 2022 (Desktop C++ Workload).
-   Flutter SDK (Stable).

**Linux:**
-   Ubuntu 20.04+ or equivalent
-   Build tools: `sudo apt install build-essential cmake pkg-config`
-   GTK: `sudo apt install libgtk-3-dev`
-   VLC: `sudo apt install vlc libvlc-dev`
-   Flutter SDK (Stable)

### Building

**Windows:**
```powershell
# Quick build with VLC bundled
.\build-with-vlc.bat

# Or manual steps:
flutter pub get
flutter build windows --release
```

**Linux:**
```bash
# Make scripts executable (first time only)
chmod +x build-linux.sh create-linux-package.sh scripts/*.sh

# Quick build (uses system VLC)
./build-linux.sh

# Build with bundled VLC (recommended for distribution)
./scripts/prepare_libvlc_bundle.sh  # Run once to create bundle
./build-linux.sh --bundle-vlc

# Create distribution packages
./create-linux-package.sh           # Creates .tar.gz
./scripts/create_deb.sh             # Creates .deb for Debian/Ubuntu
./scripts/create_rpm.sh             # Creates .rpm for Fedora/RHEL
./scripts/create_appimage.sh        # Creates AppImage (portable)

# Or build all packages at once
./scripts/build-all-packages.sh
```

See [LINUX_BUILD.md](LINUX_BUILD.md) for detailed Linux instructions.

### Common Issues
-   **"DllNotFoundException"**: Ensure `libvlc.dll` is in the build output directory (handled by `cmake` copy rules).
-   **Video covers UI**: Remember the video is a separate HWND. Use `_vlc.hideVideo()` if you need to show an overlay that isn't transparent.
-   **UI Freezing**: If you experience freezing, ensure you're using the latest version with the VLC command thread implementation.

---

## 🧵 Threading Model

```
Flutter UI Thread
    ↓
Platform channel call (non-blocking)
    ↓
Enqueue task to VLC command thread
    ↓
Return immediately to Flutter
    
VLC Command Thread (background)
    ↓
Process task queue
    ↓
Execute blocking VLC operations
    ↓
Send events via PostMessage → Platform thread
```

---

## 📁 Project Structure

```
chillz_desktop/
├── lib/
│   ├── main.dart              # UI layer, keyboard shortcuts
│   ├── services/
│   │   ├── vlc_player_service.dart    # Dart wrapper for VLC
│   │   └── iptv_service.dart          # Channel management
│   ├── models/
│   │   └── iptv_models.dart           # Data models
│   └── pages/
│       └── landing_page.dart          # Landing page UI
├── windows/
│   └── runner/
│       ├── vlc_player_plugin.cpp      # Windows native VLC integration
│       ├── vlc_player_plugin.h        # Plugin header
│       └── ...
├── linux/
│   └── runner/
│       ├── vlc_player_plugin.cc       # Linux native VLC integration
│       ├── vlc_player_plugin.h        # Plugin header
│       └── ...
├── libvlc_bundle/             # Windows VLC libraries
├── libvlc_bundle_linux/       # Linux VLC libraries (after prepare script)
├── scripts/
│   ├── bundle_libvlc.ps1      # Windows VLC bundling
│   ├── bundle_libvlc_linux.sh # Linux VLC bundling
│   └── prepare_libvlc_bundle.sh # Create Linux VLC bundle
├── build-with-vlc.bat         # Windows build script
├── build-linux.sh             # Linux build script
├── create-linux-package.sh    # Linux distribution packager
└── pubspec.yaml
```

---

## 🚀 Recent Improvements

### VLC Command Thread (Latest)
- Implemented dedicated worker thread for all blocking VLC operations
- Eliminated UI freezes when switching streams or encountering slow networks
- Proper task queue with condition variable for synchronization
- Thread-safe event dispatch via PostMessage

### Previous Improvements
- Removed blocking HTTP checks in Dart
- Fixed thread-unsafe event dispatch fallback
- Consolidated post-play timers to reduce platform channel calls

---

## 🤝 Contributing

Contributions are welcome! Please ensure:
1. All VLC operations remain on the command thread
2. No blocking calls on the UI thread
3. Proper mutex usage for shared state
4. Event dispatch via PostMessage only

---

## 📄 License

See root project LICENSE file.

---

**Built with ❤️ using Flutter and libVLC**
