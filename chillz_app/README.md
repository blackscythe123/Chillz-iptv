# Chillz App (Flutter Mobile/TV) 📱📺

**Chillz App** is a cross-platform Flutter application designed for mobile devices and Android TV, providing a native IPTV streaming experience optimized for touch and remote control interfaces.

It combines the power of Flutter's cross-platform capabilities with platform-specific optimizations for the best user experience on phones, tablets, and TV screens.

---

## 🏛️ Architecture Overview

This application uses Flutter's platform channel architecture for optimal performance:

### 1. Flutter Layer
-   **Cross-platform UI**: Single codebase for Android phones, tablets, and TV
-   **Adaptive Layouts**: Responsive design that adapts to screen size and input method
-   **State Management**: Provider pattern for clean state management
-   **Platform Channels**: Native integration for media playback

### 2. Platform-Specific Features

#### Mobile (Android/iOS)
-   **Touch Optimized**: Gesture controls for volume, seeking, brightness
-   **Picture-in-Picture**: Continue watching while using other apps
-   **Background Playback**: Audio continues when app is minimized
-   **Notifications**: Media controls in notification shade

#### Android TV
-   **D-Pad Navigation**: Full remote control support
-   **Leanback UI**: TV-optimized interface with focus management
-   **Voice Search**: Integration with Android TV voice commands
-   **Recommendations**: Channel suggestions on TV home screen

---

## ✨ Key Features

-   **Cross-Platform**: Single codebase for mobile and TV
-   **Adaptive UI**: Automatically adjusts to device type and screen size
-   **Remote Control Support**: Full D-pad and remote button mapping for TV
-   **Touch Gestures**: Swipe controls for mobile devices
-   **Channel Management**: Browse, search, and favorite channels
-   **Multi-Language**: Support for multiple audio tracks
-   **Offline Mode**: Cache channel lists for offline browsing

---

## 🛠️ Development Setup

### Prerequisites
-   Flutter SDK (Stable channel)
-   Android Studio / Xcode (for respective platforms)
-   Android device/emulator or iOS device/simulator

### Building

```bash
# Install dependencies
flutter pub get

# Run on connected device
flutter run

# Build APK for Android
flutter build apk

# Build for Android TV
flutter build apk --target-platform android-arm64 --release

# Build for iOS
flutter build ios
```

---

## 📁 Project Structure

```
chillz_app/
├── lib/
│   ├── main.dart              # App entry point
│   ├── screens/               # UI screens
│   ├── widgets/               # Reusable widgets
│   ├── services/              # Business logic
│   ├── models/                # Data models
│   └── utils/                 # Helper functions
├── android/                   # Android-specific code
├── ios/                       # iOS-specific code
└── pubspec.yaml               # Dependencies
```

---

## 📱 Platform-Specific Notes

### Android
-   Minimum SDK: 21 (Android 5.0)
-   Target SDK: Latest stable
-   Permissions: Internet, Network State

### Android TV
-   Leanback launcher support
-   TV input framework integration
-   Remote control event handling

### iOS
-   Minimum iOS: 12.0
-   AVFoundation for media playback
-   Background modes enabled

---

## 🎮 Controls

### Mobile
-   **Tap**: Play/Pause
-   **Swipe Up/Down**: Volume
-   **Swipe Left/Right**: Seek
-   **Double Tap**: Fullscreen

### Android TV
-   **D-Pad Center**: Play/Pause
-   **D-Pad Up/Down**: Channel navigation
-   **Back**: Exit fullscreen/Go back
-   **Menu**: Show options

---

## 🚀 Performance Optimizations

1.  **Lazy Loading**: Channels loaded on demand
2.  **Image Caching**: Channel logos cached locally
3.  **Memory Management**: Proper disposal of resources
4.  **Platform Channels**: Native code for heavy operations

---

## 🤝 Contributing

Contributions are welcome! Please ensure:
1. Code follows Flutter best practices
2. UI is tested on both mobile and TV
3. Platform-specific features are properly isolated
4. Performance is maintained

---

## 📄 License

See root project LICENSE file.

---

**Built with ❤️ using Flutter**
