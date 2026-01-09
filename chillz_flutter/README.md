# Chillz (Flutter Windows • libVLC)

**Chillz** is a **Windows desktop IPTV player** built with **Flutter** and **direct libVLC integration**, designed for **stable HLS playback**, **VLC-grade reliability**, and a **custom Flutter UI**.

This project embeds **libVLC natively** (child HWND) instead of relying on fragile media wrappers, ensuring better compatibility with real-world IPTV streams.

---

## Key Features

- 🎬 **Direct libVLC integration**
  - No external VLC installation required
  - Uses bundled libVLC binaries
  - Same playback core as VLC Desktop

- 🖥️ **True Windows desktop player**
  - Video rendered inside Flutter layout (no extra VLC window)
  - Fullscreen & windowed modes fully controlled by Flutter
  - Keyboard-first UX like VLC

- 📡 **Real IPTV support**
  - HLS (`.m3u8`) live streams
  - Handles unstable and imperfect IPTV sources
  - Graceful handling of broken metadata, logos, and DNS failures

- 🔊 **Advanced audio controls**
  - Multiple audio track selection
  - VLC-style volume amplification up to **200%**
  - No “ghost audio” when switching channels

- ⚡ **Performance-focused**
  - Hardware-accelerated decoding
  - Native video rendering
  - Minimal UI overhead

---

## Quick Start

### Requirements
- Windows 10 / 11 (64-bit)
- Flutter (stable channel)
- Visual Studio Build Tools (Desktop development with C++)

### Run the app

```bash
flutter pub get
flutter run -d windows
