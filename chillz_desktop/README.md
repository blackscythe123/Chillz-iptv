# Chillz Desktop (Flutter + libVLC) 🎬

**Chillz Desktop** is a native Windows IPTV player that bridges the gap between high-performance C++ media playback and modern Flutter UI.

It is built to handle the complexities of live HLS streaming that standard video players often fail at, providing a "VLC-grade" experience with a beautiful interface.

---

## 🏛️ Architecture Deep Dive

This application follows a strict 3-layer architecture to ensure stability and performance:

### 1. Native Layer (C++) - `windows/runner/vlc_player_plugin.cpp`
This is the core engine. Flutter cannot render video efficiently on its own, so we bypass it.
-   **Direct libVLC Embedding**: We link directly against `libvlc.dll` and `libvlccore.dll`.
-   **Child HWND**: The plugin creates a completely separate Windows HWND (Window Handle) that is a child of the Flutter window.
-   **Direct Rendering**: VLC renders video pixels directly into this child HWND. Use `_updateVideoBounds()` in Flutter to resize this window to match the UI layout.
-   **Event Loop**: A custom `VlcEventCallback` captures low-level libVLC events (Buffering, Errors, EOS) and sends them to Flutter via an `EventChannel`.
-   **Error Interception**: Specifically captures HTTP 403/404 errors from the VLC log to detect Geo-blocking.

### 2. Service Layer (Dart) - `lib/services/vlc_player_service.dart`
The bridge between chaos and order.
-   **Singleton Controller**: `VlcPlayerController` manages the single instance of the player.
-   **Platform Channels**:
    -   `MethodChannel`: Sends commands DOWN to C++ (Play, Stop, SetVolume).
    -   `EventChannel`: Receives state updates UP from C++ (Time, State, Errors).
-   **State Management**: Normalizes disjointed VLC states (Opening, Buffering, Playing) into a clean UI state machine.

### 3. UI Layer (Flutter) - `lib/main.dart`
The user experience.
-   **Z-Ordering Hack**: Since the video is a native HWND, it technically floats *on top* of the Flutter canvas. To show dialogs (like Audio Selection), we use `_vlc.hideVideo()` to temporarily hide the HWND so the Flutter dialog is visible.
-   **Proactive URL Check**: Before asking VLC to play, we send a quick HTTP GET request to check for 403/404 errors, giving the user instant feedback ("Use VPN") instead of a generic timeout.
-   **Input Handling**: Captures global keyboard shortcuts (Space, F, A, M) even when the video window has OS-level focus.

---

## ✨ Key Features

-   **Proactive Error Handling**: Detects Geo-blocked (403) and Dead (404) streams *before* playback.
-   **Audio Track Selection**: Full support for multi-language streams.
    -   *Shortcut*: Press `A` to toggle tracks.
-   **Volume Boost**: VLC-style amplification up to 200%.
-   **Dev Mode**: Real-time diagnostic overlay (Press the "Bug" icon).

---

## 🛠️ Development Setup

### Prerequisites
-   Windows 10/11 x64.
-   Visual Studio 2022 (Desktop C++ Workload).
-   Flutter SDK (Stable).

### Building
The `build.gradle` (or `CMakeLists.txt` for Windows) handles linking the pre-bundled VLC binaries located in `windows/runner/vlc/`.

```powershell
# Install dependencies
flutter pub get

# Run in debug mode (Hot Reload enabled)
flutter run -d windows

# Build optimized release (Reduced size, no debug console)
flutter build windows --release
```

### Common Issues
-   **"DllNotFoundException"**: Ensure `libvlc.dll` is in the build output directory (handled by `cmake` copy rules).
-   **Video covers UI**: Remember the video is a separate HWND. Use `_vlc.hideVideo()` if you need to show an overlay that isn't transparent.
