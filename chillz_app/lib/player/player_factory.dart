// Player Factory - Platform-specific player selector
// Returns the appropriate PlayerEngine implementation for the current platform

import 'dart:io';
import 'package:flutter/foundation.dart';

import 'player_engine.dart';

// Conditional imports for platform-specific players
import 'windows_player.dart' if (dart.library.html) 'player_engine.dart';
import 'android_player.dart' if (dart.library.html) 'player_engine.dart';

/// Platform detection and player factory
class PlayerFactory {
  static PlayerEngine? _instance;

  /// Check if running on Android TV
  static bool _isAndroidTV = false;

  /// Get or create the singleton player instance
  static PlayerEngine get instance {
    _instance ??= create();
    return _instance!;
  }

  /// Create a new player engine for the current platform
  static PlayerEngine create() {
    if (Platform.isWindows) {
      debugPrint('[PlayerFactory] Creating WindowsVlcPlayer');
      return WindowsVlcPlayer();
    } else if (Platform.isAndroid) {
      debugPrint('[PlayerFactory] Creating AndroidMpvPlayer');
      return AndroidMpvPlayer();
    } else if (Platform.isLinux) {
      // Linux could use either - default to MPV for now
      debugPrint('[PlayerFactory] Creating AndroidMpvPlayer for Linux');
      return AndroidMpvPlayer();
    } else if (Platform.isMacOS || Platform.isIOS) {
      // macOS/iOS would use media_kit
      debugPrint('[PlayerFactory] Creating AndroidMpvPlayer for Apple');
      return AndroidMpvPlayer();
    } else {
      throw UnsupportedError(
          'Platform ${Platform.operatingSystem} is not supported');
    }
  }

  /// Dispose the singleton instance
  static Future<void> dispose() async {
    if (_instance != null) {
      await _instance!.dispose();
      _instance = null;
    }
  }

  /// Check if current platform is Windows
  static bool get isWindows => Platform.isWindows;

  /// Check if current platform is Android
  static bool get isAndroid => Platform.isAndroid;

  /// Check if running on Android TV
  static bool get isAndroidTV => _isAndroidTV;

  /// Set Android TV mode (called from platform detection)
  static void setAndroidTV(bool isTV) {
    _isAndroidTV = isTV;
    debugPrint('[PlayerFactory] Android TV mode: $isTV');
  }

  /// Check if platform requires native HWND management (Windows)
  static bool get requiresNativeWindow => Platform.isWindows;

  /// Check if platform uses Flutter texture for video
  static bool get usesFlutterTexture => !Platform.isWindows;
}
