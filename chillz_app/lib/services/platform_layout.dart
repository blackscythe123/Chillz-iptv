// Platform Layout System - Detection and adaptive layouts for Mobile, TV, Desktop
// Provides platform-specific UI configuration and layout utilities

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../player/android_tv_utils.dart';

/// Platform types for layout decisions
enum AppPlatform {
  mobile, // Android phone, iOS
  tablet, // Android tablet, iPad
  androidTV, // Android TV (Leanback)
  desktop, // Windows, macOS, Linux
}

/// Layout modes based on screen configuration
enum LayoutMode {
  compact, // Single column, small screens (phones)
  medium, // Two columns or adaptive (tablets)
  expanded, // Full layout (TV, desktop)
}

/// Platform detection and layout configuration
class PlatformLayout {
  static AppPlatform? _platform;
  static bool _initialized = false;

  // Screen breakpoints
  static const double compactMaxWidth = 600;
  static const double mediumMaxWidth = 840;

  /// Initialize platform detection
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // First, check Android TV
    await AndroidTVUtils.init();

    if (AndroidTVUtils.isTV) {
      _platform = AppPlatform.androidTV;
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      _platform = AppPlatform.desktop;
    } else if (Platform.isAndroid || Platform.isIOS) {
      // Will determine mobile vs tablet based on screen size
      _platform = AppPlatform.mobile; // Default, may be updated
    }

    // Apply platform-specific system UI settings
    await _configureSystemUI();
  }

  static Future<void> _configureSystemUI() async {
    switch (_platform) {
      case AppPlatform.mobile:
        // Allow all orientations on mobile, prefer portrait
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
        );
        break;

      case AppPlatform.tablet:
        // Allow all orientations on tablet
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;

      case AppPlatform.androidTV:
        // Landscape only, immersive
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );
        break;

      case AppPlatform.desktop:
        // No orientation restrictions on desktop
        break;

      case null:
        break;
    }
  }

  /// Get current platform
  static AppPlatform get platform => _platform ?? AppPlatform.mobile;

  /// Check if running on mobile (phone)
  static bool get isMobile => _platform == AppPlatform.mobile;

  /// Check if running on tablet
  static bool get isTablet => _platform == AppPlatform.tablet;

  /// Check if running on Android TV
  static bool get isTV => _platform == AppPlatform.androidTV;

  /// Check if running on desktop
  static bool get isDesktop => _platform == AppPlatform.desktop;

  /// Check if running on any Android device
  static bool get isAndroid => Platform.isAndroid;

  /// Check if needs touch-friendly UI
  static bool get isTouchDevice =>
      _platform == AppPlatform.mobile || _platform == AppPlatform.tablet;

  /// Check if uses remote/keyboard navigation
  static bool get usesRemoteNavigation =>
      _platform == AppPlatform.androidTV || _platform == AppPlatform.desktop;

  /// Get layout mode based on screen size
  static LayoutMode getLayoutMode(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    // TV always uses expanded layout
    if (_platform == AppPlatform.androidTV) {
      return LayoutMode.expanded;
    }

    // Desktop uses expanded layout
    if (_platform == AppPlatform.desktop) {
      return LayoutMode.expanded;
    }

    // Mobile/tablet based on width
    if (width < compactMaxWidth) {
      return LayoutMode.compact;
    } else if (width < mediumMaxWidth) {
      return LayoutMode.medium;
    } else {
      return LayoutMode.expanded;
    }
  }

  /// Update platform based on screen metrics (call from build)
  static void updateFromContext(BuildContext context) {
    if (_platform == AppPlatform.androidTV ||
        _platform == AppPlatform.desktop) {
      return; // Don't change TV/desktop detection
    }

    final size = MediaQuery.of(context).size;

    // Tablets typically have > 7" screens
    // This is a rough heuristic based on logical pixels
    final isTabletSize = size.shortestSide >= 600;

    if (isTabletSize && _platform == AppPlatform.mobile) {
      _platform = AppPlatform.tablet;
    } else if (!isTabletSize && _platform == AppPlatform.tablet) {
      _platform = AppPlatform.mobile;
    }
  }

  /// Get screen padding based on platform
  static EdgeInsets getScreenPadding(BuildContext context) {
    switch (_platform) {
      case AppPlatform.androidTV:
        // TV overscan safe area
        return const EdgeInsets.all(48.0);

      case AppPlatform.desktop:
        return const EdgeInsets.all(16.0);

      case AppPlatform.tablet:
        return const EdgeInsets.all(24.0);

      case AppPlatform.mobile:
        return const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0);

      case null:
        return const EdgeInsets.all(16.0);
    }
  }

  /// Get appropriate text scale factor
  static double getTextScaleFactor() {
    switch (_platform) {
      case AppPlatform.androidTV:
        return 1.3;
      case AppPlatform.desktop:
        return 1.0;
      case AppPlatform.tablet:
        return 1.1;
      case AppPlatform.mobile:
      case null:
        return 1.0;
    }
  }

  /// Get channel list item height
  static double getChannelItemHeight() {
    switch (_platform) {
      case AppPlatform.androidTV:
        return 72.0;
      case AppPlatform.desktop:
        return 56.0;
      case AppPlatform.tablet:
        return 64.0;
      case AppPlatform.mobile:
      case null:
        return 72.0;
    }
  }

  /// Check if should show channel list alongside player
  static bool shouldShowSideBySide(BuildContext context) {
    final mode = getLayoutMode(context);
    return mode == LayoutMode.expanded || mode == LayoutMode.medium;
  }

  /// Get channel list width for side-by-side layout
  static double getChannelListWidth(BuildContext context) {
    final size = MediaQuery.of(context).size;

    switch (_platform) {
      case AppPlatform.androidTV:
        return 350.0;
      case AppPlatform.desktop:
        return 320.0;
      case AppPlatform.tablet:
        return 280.0;
      case AppPlatform.mobile:
      case null:
        return size.width; // Full width on mobile
    }
  }
}

/// Responsive builder widget
class AdaptiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? tv;
  final Widget? desktop;

  const AdaptiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.tv,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    PlatformLayout.updateFromContext(context);

    switch (PlatformLayout.platform) {
      case AppPlatform.androidTV:
        return tv ?? desktop ?? mobile;
      case AppPlatform.desktop:
        return desktop ?? mobile;
      case AppPlatform.tablet:
        return tablet ?? mobile;
      case AppPlatform.mobile:
        return mobile;
    }
  }
}

/// Layout builder based on LayoutMode
class ResponsiveLayoutBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, LayoutMode mode) builder;

  const ResponsiveLayoutBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final mode = PlatformLayout.getLayoutMode(context);
    return builder(context, mode);
  }
}

/// Mobile-specific screen wrapper
/// Ensures portrait orientation and proper safe areas
class MobileScreen extends StatefulWidget {
  final Widget child;
  final bool forcePortrait;

  const MobileScreen({
    super.key,
    required this.child,
    this.forcePortrait = true,
  });

  @override
  State<MobileScreen> createState() => _MobileScreenState();
}

class _MobileScreenState extends State<MobileScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.forcePortrait && PlatformLayout.isMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  @override
  void dispose() {
    // Restore all orientations when leaving
    if (widget.forcePortrait && PlatformLayout.isMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: widget.child);
  }
}

/// Fullscreen player wrapper for mobile
/// Forces landscape orientation during playback
class FullscreenPlayer extends StatefulWidget {
  final Widget child;

  const FullscreenPlayer({
    super.key,
    required this.child,
  });

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer> {
  @override
  void initState() {
    super.initState();
    if (PlatformLayout.isMobile) {
      // Force landscape for video playback
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      // Hide system UI
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    if (PlatformLayout.isMobile) {
      // Restore portrait when exiting player
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      // Restore system UI
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
