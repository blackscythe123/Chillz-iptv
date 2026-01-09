# chillz_flutter

Flutter Windows desktop IPTV player using **libvlc** for reliable video playback.

## Quick Start

```bash
# Get dependencies
flutter pub get

# Run the app
flutter run -d windows
```

> **Note:** Due to Windows path length limits, if your project is in a deeply nested folder (like OneDrive), you may need to copy it to a shorter path like `C:\Temp\chillz_flutter` before building.

## How It Works

- **Self-contained**: Uses **libvlc** which bundles all required video libraries automatically
- **No external dependencies**: Everything needed for video playback is included
- **Hardware acceleration**: Supports hardware-accelerated video decoding
- **Real IPTV data**: Fetches channels from iptv-org with search/filters

## Controls & Shortcuts 🔧

- UI: A **Fullscreen** button has been added to the main controls (to the right of the speaker/mute button).
- Keyboard shortcuts:
  - `Space` — Play / Pause
  - `F` — Toggle Fullscreen
  - `Esc` — Exit Fullscreen
  - `S` — Stop
  - `A` — Audio Track dialog
  - `M` — Mute
  - `R` — Retry
  - `↑/↓` — Volume up / down

Tip: The shortcuts will not trigger while typing in any search or filter input fields to avoid accidental actions.

