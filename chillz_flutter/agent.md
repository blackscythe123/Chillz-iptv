# Chillz Flutter IPTV Player - Agent Documentation

## Overview
**Chillz** is a Windows desktop IPTV player built with Flutter using the `media_kit` framework. This document serves as a guide for AI agents to understand the project structure, build process, and deployment workflow.

## Project Paths & Structure

### Original Development Location
```
c:\Users\sam\OneDrive\one drive back up\OneDrive - SSN-Institute\Documents\projects\Chillz-in-browser\chillz_flutter\
```

### Temp Build Location (Required for Windows)
```
C:\Temp\chillz_flutter\
```
⚠️ **Important**: Due to Windows 260-character path limits, the project MUST be built from the temp location.

### Key Files & Directories
```
chillz_flutter/
├── lib/
│   ├── main.dart                 # Main application entry point
│   ├── models/
│   │   └── iptv_models.dart     # Channel data models
│   └── services/
│       └── iptv_service.dart    # Channel loading service
├── pubspec.yaml                 # Dependencies and configuration
├── windows/                     # Windows-specific build files
└── build/                       # Generated build outputs
```

## Dependencies & Packages

### Core Dependencies (pubspec.yaml)
```yaml
dependencies:
  flutter:
    sdk: flutter
  # Modern cross-platform media player using libmpv/libvlc
  media_kit: ^1.1.10+1
  media_kit_video: ^1.2.4
  media_kit_libs_windows_video: ^1.0.9
  provider: ^6.1.5+1
  http: ^0.13.6
  path_provider: ^2.0.13
  json_annotation: ^4.8.0
```

### Key Features Implemented
- ✅ **Stream Quality Selection**: Auto, 1080p, 720p, 480p, 360p, 240p
- ✅ **Enhanced Search & Filtering**: Debounced search, category/country/language filters with chip UI
- ✅ **Keyboard Shortcuts**: Space (play/pause), F (fullscreen), A (audio), Q (quality), M (mute), R (retry), ↑/↓ (volume)
- ✅ **Audio Track Selection**: Enhanced dialog showing language, codec info, track IDs
- ✅ **Modern UI**: Gradient backgrounds, rounded corners, status badges, hover effects
- ✅ **Error Handling**: URL availability checking, user-friendly error messages, retry functionality
- ✅ **Smart Channel Sorting**: Search relevance scoring, alphabetical category sorting

## Build & Deployment Process

### Step 1: Copy Project to Temp Location
```powershell
# Create temp directory if it doesn't exist
New-Item -ItemType Directory -Force -Path "C:\Temp\chillz_flutter"

# Copy entire project (excluding build folder)
robocopy "c:\Users\sam\OneDrive\one drive back up\OneDrive - SSN-Institute\Documents\projects\Chillz-in-browser\chillz_flutter" "C:\Temp\chillz_flutter" /E /XD build .dart_tool
```

### Step 2: Update Main Dart File
```powershell
# Copy updated main.dart
Copy-Item -Force "c:\Users\sam\OneDrive\one drive back up\OneDrive - SSN-Institute\Documents\projects\Chillz-in-browser\chillz_flutter\lib\main.dart" "C:\Temp\chillz_flutter\lib\main.dart"
```

### Step 3: Build and Run
```powershell
# Navigate to temp folder
Push-Location "C:\Temp\chillz_flutter"

# Clean previous builds
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
flutter clean

# Get dependencies
flutter pub get

# Run on Windows
flutter run -d windows

# When done, return to original location
Pop-Location
```

## Architecture & Code Structure

### Main Components

#### 1. State Management
- **Provider Pattern**: Uses `IptvService` for channel data management
- **Local State**: `_ChillzHomeState` manages player, UI, and user interactions

#### 2. Media Playback
- **media_kit Player**: Cross-platform video player with libVLC backend
- **VideoController**: Manages video rendering and controls
- **Error Handling**: Pre-checks URLs, handles timeouts, provides fallbacks

#### 3. UI Components
- **Left Panel**: Enhanced search, filter chips, channel list with cards
- **Center Panel**: Video player with contextual states (loading, error, playing)
- **Controls**: Modern button styling with keyboard shortcut hints
- **Diagnostics**: Colorful status badges and error reporting

#### 4. Search & Filtering
```dart
// Debounced search implementation
Timer? _searchTimer;
void _updateSearch(String query) {
  _searchTimer?.cancel();
  _searchTimer = Timer(const Duration(milliseconds: 300), () {
    setState(() => _searchQuery = query.trim().toLowerCase());
  });
}

// Search relevance scoring
int _calculateSearchScore(dynamic channel, String query) {
  int score = 0;
  if (channel.name.toLowerCase().startsWith(query)) score += 100;
  // ... additional scoring logic
  return score;
}
```

#### 5. Keyboard Shortcuts Implementation
```dart
void _handleKeyEvent(KeyEvent event) {
  if (event is! KeyDownEvent) return;
  
  switch (event.logicalKey) {
    case LogicalKeyboardKey.space: _playPause(); break;
    case LogicalKeyboardKey.keyF: _toggleFullscreen(); break;
    case LogicalKeyboardKey.keyA: _showAudioTrackDialog(); break;
    // ... more shortcuts
  }
}
```

## Common Issues & Solutions

### 1. Path Length Limitations
**Problem**: Windows 260-character path limit causes build failures
**Solution**: Always build from `C:\Temp\chillz_flutter\`

### 2. Media Kit Initialization
**Problem**: "media_kit not initialized" errors
**Solution**: Ensure `MediaKit.ensureInitialized()` is called in `main()`

### 3. Audio Track Issues
**Problem**: "Error decoding audio" in diagnostics
**Solution**: Enhanced error handling catches audio codec issues gracefully

### 4. Stream Availability
**Problem**: Streams fail to load without clear error messages
**Solution**: Pre-flight HTTP HEAD requests check URL availability

## Development Workflow for Agents

### When Making Changes:
1. **Edit** files in the original OneDrive location
2. **Copy** updated files to temp location
3. **Build & Test** from temp location
4. **Document** changes in this file

### File Update Command Template:
```powershell
# Copy specific file after editing
Copy-Item -Force "c:\Users\sam\OneDrive\one drive back up\OneDrive - SSN-Institute\Documents\projects\Chillz-in-browser\chillz_flutter\lib\main.dart" "C:\Temp\chillz_flutter\lib\main.dart"

# Run app to test
Push-Location "C:\Temp\chillz_flutter"
flutter run -d windows
Pop-Location
```

### Testing Checklist:
- [ ] App launches without errors
- [ ] Channel list loads and displays properly
- [ ] Search and filtering work with debounce
- [ ] Video playback starts successfully
- [ ] Audio track selection shows available languages
- [ ] Quality selector appears and functions
- [ ] Keyboard shortcuts respond correctly
- [ ] Error states display user-friendly messages
- [ ] Fullscreen mode works with ESC to exit

## Performance Optimizations

### Search Performance
- Debounced search input (300ms delay)
- Relevance-based sorting algorithm
- Efficient filtering with early returns

### Memory Management
- Proper player disposal on route changes
- Timer cleanup in dispose methods
- Image caching for channel logos

### UI Responsiveness
- Async loading states with progress indicators
- Non-blocking URL availability checks
- Background stream processing

## Debugging Tips

### Common Log Messages:
- `"Cannot load nvcuda.dll"` - Safe to ignore (NVIDIA CUDA not available)
- `"Error decoding audio"` - Check audio track selection and stream format
- `"Stream not found (404)"` - URL pre-check working correctly
- `"Connection timed out"` - Network or server issue, retry recommended

### Flutter DevTools:
Access at: `http://127.0.0.1:9101?uri=http://127.0.0.1:[PORT]/[ID]/`

## Version History

### Current Version: 0.1.0+enhancements
- Enhanced search and filtering with chip UI
- Stream quality selection dialog
- Comprehensive keyboard shortcuts
- Modern UI with gradients and cards
- Improved audio track selection
- Smart error handling and retry logic

### Previous Version: 0.1.0+media_kit
- Basic media_kit integration
- Simple channel list and playback
- Basic error handling

---

**Last Updated**: January 2026
**Maintained By**: AI Agent Collective
**Flutter Version**: >=3.3.0 <4.0.0
**Target Platform**: Windows Desktop