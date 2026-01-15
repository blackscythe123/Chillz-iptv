// Android TV Utilities - Detection, focus management, and remote control support
// Provides D-pad navigation, focus highlighting, and TV-specific UI adaptations

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android TV detection and utilities
class AndroidTVUtils {
  static bool _isTV = false;
  static bool _initialized = false;

  /// Check if running on Android TV
  static bool get isTV => _isTV;

  /// Initialize TV detection
  /// Call this early in app startup
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (!Platform.isAndroid) {
      _isTV = false;
      return;
    }

    try {
      // Check for Leanback feature
      const platform = MethodChannel('com.chillz/platform');
      final result = await platform.invokeMethod<bool>('isAndroidTV');
      _isTV = result ?? false;
      debugPrint('[AndroidTV] Detection result: $_isTV');
    } catch (e) {
      // Fallback: check for common TV characteristics
      _isTV = await _fallbackTVDetection();
      debugPrint('[AndroidTV] Fallback detection result: $_isTV');
    }

    if (_isTV) {
      // Force landscape on TV
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      // Hide system UI for immersive experience
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
    }
  }

  static Future<bool> _fallbackTVDetection() async {
    // Check screen size - TVs typically have large screens
    // This is a rough heuristic
    final window = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = window.physicalSize / window.devicePixelRatio;

    // TVs typically have diagonal > 30 inches
    // Assuming ~160 DPI, that's roughly 1920x1080 at scale 1
    final isLargeScreen = size.width >= 1280 && size.height >= 720;

    return isLargeScreen;
  }

  /// Get appropriate text scale for TV
  static double get textScaleFactor => _isTV ? 1.3 : 1.0;

  /// Get appropriate icon scale for TV
  static double get iconScaleFactor => _isTV ? 1.4 : 1.0;

  /// Get appropriate padding for TV
  static EdgeInsets get screenPadding =>
      _isTV ? const EdgeInsets.all(48.0) : const EdgeInsets.all(16.0);

  /// Get focus border for TV navigation
  static BoxDecoration focusDecoration({bool focused = false}) {
    if (!_isTV || !focused) return const BoxDecoration();

    return BoxDecoration(
      border: Border.all(
        color: Colors.white,
        width: 3,
      ),
      borderRadius: BorderRadius.circular(8),
      boxShadow: [
        BoxShadow(
          color: Colors.blue.withOpacity(0.5),
          blurRadius: 12,
          spreadRadius: 2,
        ),
      ],
    );
  }
}

/// A widget that provides focus handling for Android TV
/// Wraps child with focus management and visual feedback
class TVFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final VoidCallback? onFocused;
  final bool autofocus;
  final FocusNode? focusNode;

  const TVFocusable({
    Key? key,
    required this.child,
    this.onSelect,
    this.onFocused,
    this.autofocus = false,
    this.focusNode,
  }) : super(key: key);

  @override
  State<TVFocusable> createState() => _TVFocusableState();
}

class _TVFocusableState extends State<TVFocusable> {
  late FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _focused = _focusNode.hasFocus;
    });
    if (_focused) {
      widget.onFocused?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AndroidTVUtils.isTV) {
      // Non-TV: just return child with tap handler
      return GestureDetector(
        onTap: widget.onSelect,
        child: widget.child,
      );
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Handle D-pad select (Enter/OK)
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            widget.onSelect?.call();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform:
            _focused ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
        decoration: AndroidTVUtils.focusDecoration(focused: _focused),
        child: widget.child,
      ),
    );
  }
}

/// Remote control handler for Android TV
/// Handles Back button, media keys, etc.
class TVRemoteHandler extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onPlayPause;
  final VoidCallback? onStop;
  final VoidCallback? onForward;
  final VoidCallback? onRewind;
  final VoidCallback? onVolumeUp;
  final VoidCallback? onVolumeDown;

  const TVRemoteHandler({
    Key? key,
    required this.child,
    this.onBack,
    this.onPlayPause,
    this.onStop,
    this.onForward,
    this.onRewind,
    this.onVolumeUp,
    this.onVolumeDown,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;

        final key = event.logicalKey;

        // Back button
        if (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.browserBack) {
          onBack?.call();
          return;
        }

        // Media keys
        if (key == LogicalKeyboardKey.mediaPlayPause ||
            key == LogicalKeyboardKey.space) {
          onPlayPause?.call();
          return;
        }

        if (key == LogicalKeyboardKey.mediaStop) {
          onStop?.call();
          return;
        }

        if (key == LogicalKeyboardKey.mediaFastForward ||
            key == LogicalKeyboardKey.arrowRight) {
          onForward?.call();
          return;
        }

        if (key == LogicalKeyboardKey.mediaRewind ||
            key == LogicalKeyboardKey.arrowLeft) {
          onRewind?.call();
          return;
        }

        // Volume
        if (key == LogicalKeyboardKey.audioVolumeUp ||
            key == LogicalKeyboardKey.arrowUp) {
          onVolumeUp?.call();
          return;
        }

        if (key == LogicalKeyboardKey.audioVolumeDown ||
            key == LogicalKeyboardKey.arrowDown) {
          onVolumeDown?.call();
          return;
        }
      },
      child: child,
    );
  }
}

/// Focus traversal group for TV grid navigation
class TVFocusGroup extends StatelessWidget {
  final Widget child;
  final FocusTraversalPolicy? policy;

  const TVFocusGroup({
    super.key,
    required this.child,
    this.policy,
  });

  @override
  Widget build(BuildContext context) {
    if (!AndroidTVUtils.isTV) {
      return child;
    }

    return FocusTraversalGroup(
      policy: policy ?? WidgetOrderTraversalPolicy(),
      child: child,
    );
  }
}
