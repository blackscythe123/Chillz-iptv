# chillz_flutter

Flutter Windows desktop IPTV player using **media_kit** for reliable video playback.

## Quick Start

```bash
# Get dependencies
flutter pub get

# Run the app
flutter run -d windows
```

> **Note:** Due to Windows path length limits, if your project is in a deeply nested folder (like OneDrive), you may need to copy it to a shorter path like `C:\Temp\chillz_flutter` before building.

## How It Works

- **Self-contained**: Uses **media_kit** which bundles all required video libraries automatically
- **No external dependencies**: Everything needed for video playback is included
- **Hardware acceleration**: Supports hardware-accelerated video decoding
- **Real IPTV data**: Fetches channels from iptv-org with search/filters

## Dependencies

The app uses:
- `media_kit` - Modern video player for Flutter
- `media_kit_video` - Video widget
- `media_kit_libs_windows_video` - Bundled native libraries for Windows

