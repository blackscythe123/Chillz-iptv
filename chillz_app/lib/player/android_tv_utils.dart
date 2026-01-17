// Android TV Utilities - Detection, focus management, and remote control support
// Provides D-pad navigation, focus highlighting, and TV-specific UI adaptations
// Enhanced with comprehensive remote key handling for IPTV apps

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV Remote Key Actions for IPTV app
enum TVRemoteAction {
  // D-pad navigation
  up,
  down,
  left,
  right,
  select, // OK/Enter
  back,

  // Media playback
  playPause,
  play,
  pause,
  stop,
  fastForward,
  rewind,
  channelUp,
  channelDown,

  // Volume
  volumeUp,
  volumeDown,
  mute,

  // Number keys for channel input
  num0,
  num1,
  num2,
  num3,
  num4,
  num5,
  num6,
  num7,
  num8,
  num9,

  // Other
  menu,
  info,
  guide,
  none,
}

/// Android TV detection and utilities
class AndroidTVUtils {
  static bool _isTV = false;
  static bool _initialized = false;

  /// Check if running on Android TV
  static bool get isTV => _isTV;

  /// Check if running on Android (phone or TV)
  static bool get isAndroid => Platform.isAndroid;

  /// Check if running on Android phone (not TV)
  static bool get isAndroidPhone => Platform.isAndroid && !_isTV;

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

  /// Parse key event to TV remote action
  static TVRemoteAction parseKeyEvent(KeyEvent event) {
    final key = event.logicalKey;

    // D-pad navigation
    if (key == LogicalKeyboardKey.arrowUp) return TVRemoteAction.up;
    if (key == LogicalKeyboardKey.arrowDown) return TVRemoteAction.down;
    if (key == LogicalKeyboardKey.arrowLeft) return TVRemoteAction.left;
    if (key == LogicalKeyboardKey.arrowRight) return TVRemoteAction.right;

    // Select/OK
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.numpadEnter) {
      return TVRemoteAction.select;
    }

    // Back
    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.gameButtonB) {
      return TVRemoteAction.back;
    }

    // Media playback
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space) {
      return TVRemoteAction.playPause;
    }
    if (key == LogicalKeyboardKey.mediaPlay) return TVRemoteAction.play;
    if (key == LogicalKeyboardKey.mediaPause) return TVRemoteAction.pause;
    if (key == LogicalKeyboardKey.mediaStop) return TVRemoteAction.stop;
    if (key == LogicalKeyboardKey.mediaFastForward) {
      return TVRemoteAction.fastForward;
    }
    if (key == LogicalKeyboardKey.mediaRewind) return TVRemoteAction.rewind;
    if (key == LogicalKeyboardKey.channelUp) return TVRemoteAction.channelUp;
    if (key == LogicalKeyboardKey.channelDown) {
      return TVRemoteAction.channelDown;
    }

    // Volume
    if (key == LogicalKeyboardKey.audioVolumeUp) return TVRemoteAction.volumeUp;
    if (key == LogicalKeyboardKey.audioVolumeDown) {
      return TVRemoteAction.volumeDown;
    }
    if (key == LogicalKeyboardKey.audioVolumeMute) return TVRemoteAction.mute;

    // Number keys
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      return TVRemoteAction.num0;
    }
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      return TVRemoteAction.num1;
    }
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
      return TVRemoteAction.num2;
    }
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
      return TVRemoteAction.num3;
    }
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
      return TVRemoteAction.num4;
    }
    if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
      return TVRemoteAction.num5;
    }
    if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
      return TVRemoteAction.num6;
    }
    if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
      return TVRemoteAction.num7;
    }
    if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
      return TVRemoteAction.num8;
    }
    if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
      return TVRemoteAction.num9;
    }

    // Menu/Info
    if (key == LogicalKeyboardKey.contextMenu) return TVRemoteAction.menu;
    if (key == LogicalKeyboardKey.info) return TVRemoteAction.info;
    // Note: tvGuide key is not available in all Flutter versions

    return TVRemoteAction.none;
  }

  /// Get numeric value from number key action
  static int? getNumberFromAction(TVRemoteAction action) {
    switch (action) {
      case TVRemoteAction.num0:
        return 0;
      case TVRemoteAction.num1:
        return 1;
      case TVRemoteAction.num2:
        return 2;
      case TVRemoteAction.num3:
        return 3;
      case TVRemoteAction.num4:
        return 4;
      case TVRemoteAction.num5:
        return 5;
      case TVRemoteAction.num6:
        return 6;
      case TVRemoteAction.num7:
        return 7;
      case TVRemoteAction.num8:
        return 8;
      case TVRemoteAction.num9:
        return 9;
      default:
        return null;
    }
  }
}

/// A widget that provides focus handling for Android TV
/// Wraps child with focus management and visual feedback
class TVFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final VoidCallback? onFocused;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool enableScale;

  const TVFocusable({
    super.key,
    required this.child,
    this.onSelect,
    this.onFocused,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
    this.autofocus = false,
    this.focusNode,
    this.enableScale = true,
  });

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
          final action = AndroidTVUtils.parseKeyEvent(event);

          switch (action) {
            case TVRemoteAction.select:
              widget.onSelect?.call();
              return KeyEventResult.handled;
            case TVRemoteAction.left:
              if (widget.onLeft != null) {
                widget.onLeft!();
                return KeyEventResult.handled;
              }
              break;
            case TVRemoteAction.right:
              if (widget.onRight != null) {
                widget.onRight!();
                return KeyEventResult.handled;
              }
              break;
            case TVRemoteAction.up:
              if (widget.onUp != null) {
                widget.onUp!();
                return KeyEventResult.handled;
              }
              break;
            case TVRemoteAction.down:
              if (widget.onDown != null) {
                widget.onDown!();
                return KeyEventResult.handled;
              }
              break;
            default:
              break;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: _focused && widget.enableScale
            ? (Matrix4.identity()..scale(1.05))
            : Matrix4.identity(),
        decoration: AndroidTVUtils.focusDecoration(focused: _focused),
        child: widget.child,
      ),
    );
  }
}

/// Remote control handler for Android TV
/// Handles Back button, media keys, D-pad navigation for IPTV
class TVRemoteHandler extends StatefulWidget {
  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onPlayPause;
  final VoidCallback? onStop;
  final VoidCallback? onForward;
  final VoidCallback? onRewind;
  final VoidCallback? onVolumeUp;
  final VoidCallback? onVolumeDown;
  final VoidCallback? onMute;
  final VoidCallback? onChannelUp;
  final VoidCallback? onChannelDown;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onSelect;
  final VoidCallback? onMenu;
  final VoidCallback? onInfo;
  final void Function(int number)? onNumberKey;
  final FocusNode? focusNode;

  const TVRemoteHandler({
    super.key,
    required this.child,
    this.onBack,
    this.onPlayPause,
    this.onStop,
    this.onForward,
    this.onRewind,
    this.onVolumeUp,
    this.onVolumeDown,
    this.onMute,
    this.onChannelUp,
    this.onChannelDown,
    this.onUp,
    this.onDown,
    this.onLeft,
    this.onRight,
    this.onSelect,
    this.onMenu,
    this.onInfo,
    this.onNumberKey,
    this.focusNode,
  });

  @override
  State<TVRemoteHandler> createState() => _TVRemoteHandlerState();
}

class _TVRemoteHandlerState extends State<TVRemoteHandler> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final action = AndroidTVUtils.parseKeyEvent(event);

    switch (action) {
      // Navigation
      case TVRemoteAction.back:
        widget.onBack?.call();
        return widget.onBack != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      case TVRemoteAction.up:
        widget.onUp?.call();
        return widget.onUp != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      case TVRemoteAction.down:
        widget.onDown?.call();
        return widget.onDown != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      case TVRemoteAction.left:
        widget.onLeft?.call();
        return widget.onLeft != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      case TVRemoteAction.right:
        widget.onRight?.call();
        return widget.onRight != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      case TVRemoteAction.select:
        widget.onSelect?.call();
        return widget.onSelect != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      // Media playback
      case TVRemoteAction.playPause:
        widget.onPlayPause?.call();
        return widget.onPlayPause != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      case TVRemoteAction.stop:
        widget.onStop?.call();
        return widget.onStop != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      case TVRemoteAction.fastForward:
        widget.onForward?.call();
        return widget.onForward != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      case TVRemoteAction.rewind:
        widget.onRewind?.call();
        return widget.onRewind != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      case TVRemoteAction.channelUp:
        widget.onChannelUp?.call();
        return widget.onChannelUp != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      case TVRemoteAction.channelDown:
        widget.onChannelDown?.call();
        return widget.onChannelDown != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      // Volume
      case TVRemoteAction.volumeUp:
        widget.onVolumeUp?.call();
        return widget.onVolumeUp != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      case TVRemoteAction.volumeDown:
        widget.onVolumeDown?.call();
        return widget.onVolumeDown != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      case TVRemoteAction.mute:
        widget.onMute?.call();
        return widget.onMute != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      // Menu/Info
      case TVRemoteAction.menu:
        widget.onMenu?.call();
        return widget.onMenu != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      case TVRemoteAction.info:
        widget.onInfo?.call();
        return widget.onInfo != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;

      // Number keys
      case TVRemoteAction.num0:
      case TVRemoteAction.num1:
      case TVRemoteAction.num2:
      case TVRemoteAction.num3:
      case TVRemoteAction.num4:
      case TVRemoteAction.num5:
      case TVRemoteAction.num6:
      case TVRemoteAction.num7:
      case TVRemoteAction.num8:
      case TVRemoteAction.num9:
        final number = AndroidTVUtils.getNumberFromAction(action);
        if (number != null && widget.onNumberKey != null) {
          widget.onNumberKey!(number);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;

      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
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

/// Number input collector for TV remotes
/// Allows channel number input with auto-submit after timeout
class TVNumberInputCollector {
  String _digits = '';
  DateTime? _lastInput;
  final Duration timeout;
  final void Function(int channelNumber)? onChannelSubmit;

  TVNumberInputCollector({
    this.timeout = const Duration(seconds: 2),
    this.onChannelSubmit,
  });

  void addDigit(int digit) {
    final now = DateTime.now();

    // Reset if timeout elapsed
    if (_lastInput != null && now.difference(_lastInput!) > timeout) {
      _digits = '';
    }

    _digits += digit.toString();
    _lastInput = now;

    // Limit to 4 digits (max channel 9999)
    if (_digits.length >= 4) {
      _submitAndReset();
    } else {
      // Schedule auto-submit after timeout
      Future.delayed(timeout, () {
        if (_digits.isNotEmpty) {
          final elapsed = DateTime.now().difference(_lastInput ?? now);
          if (elapsed >= timeout) {
            _submitAndReset();
          }
        }
      });
    }
  }

  void _submitAndReset() {
    if (_digits.isNotEmpty) {
      final number = int.tryParse(_digits) ?? 0;
      onChannelSubmit?.call(number);
      _digits = '';
    }
  }

  String get currentInput => _digits;

  void clear() {
    _digits = '';
    _lastInput = null;
  }
}

/// Directional focus navigation helper for TV
class TVDirectionalFocus {
  /// Move focus to the next focusable widget in a direction
  static bool moveFocus(BuildContext context, TraversalDirection direction) {
    final scope = FocusScope.of(context);
    switch (direction) {
      case TraversalDirection.up:
        return scope.focusInDirection(TraversalDirection.up);
      case TraversalDirection.down:
        return scope.focusInDirection(TraversalDirection.down);
      case TraversalDirection.left:
        return scope.focusInDirection(TraversalDirection.left);
      case TraversalDirection.right:
        return scope.focusInDirection(TraversalDirection.right);
    }
  }

  /// Request focus on first focusable child
  static void focusFirst(BuildContext context) {
    final scope = FocusScope.of(context);
    scope.nextFocus();
  }

  /// Request focus on a specific node
  static void focusNode(FocusNode node) {
    node.requestFocus();
  }
}
