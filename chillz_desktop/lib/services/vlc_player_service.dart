// VLC Player Service - Dart wrapper for native libVLC integration
// This is UI-only code - all playback handled by native libVLC
// NO media_kit, NO FFmpeg - pure VLC behavior

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// VLC playback state
enum VlcState {
  idle,
  opening,
  buffering,
  playing,
  paused,
  stopped,
  ended,
  error,
}

/// Audio track information
class VlcAudioTrack {
  final int id;
  final String name;

  VlcAudioTrack({required this.id, required this.name});

  @override
  String toString() => 'VlcAudioTrack($id: $name)';
}

/// VLC Player Controller - wraps native libVLC via platform channel
class VlcPlayerController with ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('com.chillz/vlc_player');
  static const EventChannel _eventChannel =
      EventChannel('com.chillz/vlc_player_events');

  // State
  VlcState _state = VlcState.idle;
  bool _initialized = false;
  bool _isPlaying = false;
  int _volume = 100;
  bool _isMuted = false;
  List<VlcAudioTrack> _audioTracks = [];
  int _currentAudioTrack = -1;
  int _videoWidth = 0;
  int _videoHeight = 0;
  int _textureId = -1;
  String? _currentUrl;
  String? _lastError;

  // Event subscription
  StreamSubscription? _eventSubscription;

  // Getters
  VlcState get state => _state;
  bool get initialized => _initialized;
  bool get isPlaying => _isPlaying;
  int get volume => _volume;
  bool get isMuted => _isMuted;
  List<VlcAudioTrack> get audioTracks => _audioTracks;
  int get currentAudioTrack => _currentAudioTrack;
  int get videoWidth => _videoWidth;
  int get videoHeight => _videoHeight;
  int get textureId => _textureId;
  String? get currentUrl => _currentUrl;
  String? get lastError => _lastError;

  /// Initialize VLC with plugins path
  /// This automatically creates the child HWND for video rendering
  Future<bool> initialize({String? pluginsPath}) async {
    if (_initialized) return true;

    try {
      // Default plugins path - relative to executable
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;

      // Platform-specific plugins path
      String defaultPluginsPath;
      if (Platform.isWindows) {
        defaultPluginsPath = '$exeDir\\plugins';
      } else if (Platform.isLinux) {
        // On Linux, plugins are in lib/vlc/plugins
        defaultPluginsPath = '$exeDir/lib/vlc/plugins';
      } else {
        defaultPluginsPath = '$exeDir/plugins';
      }

      final path = pluginsPath ?? defaultPluginsPath;
      debugPrint('[VLC] Initializing with plugins: $path');

      final result = await _channel.invokeMethod<bool>('initialize', {
        'pluginsPath': path,
      });

      if (result == true) {
        _initialized = true;
        _subscribeToEvents();
        debugPrint('[VLC] Initialized successfully');

        // CRITICAL: The native side now creates the child HWND automatically
        // in Initialize(). We no longer need to call attachVideo() separately.
        // The HWND is created and attached to the media player before any Play().
        debugPrint(
            '[VLC] Child HWND created automatically by native Initialize');

        notifyListeners();
        return true;
      }

      debugPrint('[VLC] Initialize returned false');
      return false;
    } catch (e) {
      debugPrint('[VLC] Initialize error: $e');
      _lastError = e.toString();
      return false;
    }
  }

  /// Subscribe to native VLC events
  void _subscribeToEvents() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          _handleEvent(Map<String, dynamic>.from(event));
        }
      },
      onError: (error) {
        debugPrint('[VLC] Event stream error: $error');
      },
    );
  }

  /// Handle events from native VLC
  void _handleEvent(Map<String, dynamic> event) {
    final eventName = event['event'] as String?;
    debugPrint('[VLC] Event: $eventName - $event');

    switch (eventName) {
      case 'playbackState':
        final stateStr = event['state'] as String?;
        _updateState(stateStr);
        break;

      case 'videoSize':
        _videoWidth = event['width'] as int? ?? 0;
        _videoHeight = event['height'] as int? ?? 0;
        notifyListeners();
        break;

      case 'error':
        final errorMsg = event['error'] as String?;
        final recoverable = event['recoverable'] as bool? ?? true;
        _lastError = errorMsg;
        if (!recoverable) {
          _state = VlcState.error;
        }
        // VLC handles errors internally - we just log
        debugPrint('[VLC] Error (recoverable=$recoverable): $errorMsg');
        notifyListeners();
        break;

      case 'initialized':
        _initialized = event['initialized'] as bool? ?? false;
        notifyListeners();
        break;
    }
  }

  void _updateState(String? stateStr) {
    final oldState = _state;
    switch (stateStr) {
      case 'opening':
        _state = VlcState.opening;
        break;
      case 'buffering':
        _state = VlcState.buffering;
        break;
      case 'playing':
        _state = VlcState.playing;
        _isPlaying = true;
        // CRITICAL: Reapply volume when playback starts
        // Volume >100% may require media to be playing
        if (_volume != 100) {
          Future.delayed(const Duration(milliseconds: 200), () {
            debugPrint('[VLC] State=playing: reapplying volume $_volume%');
            setVolume(_volume);
          });
        }
        break;
      case 'paused':
        _state = VlcState.paused;
        _isPlaying = false;
        break;
      case 'stopped':
        _state = VlcState.stopped;
        _isPlaying = false;
        break;
      case 'ended':
        _state = VlcState.ended;
        _isPlaying = false;
        break;
      default:
        _state = VlcState.idle;
    }

    if (oldState != _state) {
      debugPrint('[VLC] State: $oldState -> $_state');
      notifyListeners();
    }
  }

  /// Play a media URL (HLS, IPTV, etc.)
  Future<bool> play(String url) async {
    if (!_initialized) {
      debugPrint('[VLC] Not initialized, initializing first...');
      final initOk = await initialize();
      if (!initOk) return false;
    }

    try {
      debugPrint('[VLC] Playing: $url');
      _currentUrl = url;
      _state = VlcState.opening;
      _lastError = null;
      notifyListeners();

      final result = await _channel.invokeMethod<bool>('play', {
        'url': url,
      });

      if (result == true) {
        // CRITICAL: Reapply volume after playback starts
        // Volume >100 may not stick until media is playing
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_volume > 0) {
            debugPrint('[VLC] Reapplying volume after play: $_volume%');
            setVolume(_volume);
          }
        });

        // Refresh audio tracks after a short delay
        Future.delayed(const Duration(seconds: 2), () {
          refreshAudioTracks();
        });
        return true;
      }

      _state = VlcState.error;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('[VLC] Play error: $e');
      _lastError = e.toString();
      _state = VlcState.error;
      notifyListeners();
      return false;
    }
  }

  /// Stop playback - CRITICAL for preventing ghost audio
  Future<void> stop() async {
    if (!_initialized) return;

    try {
      debugPrint('[VLC] Stopping playback');
      await _channel.invokeMethod('stop');
      _isPlaying = false;
      _state = VlcState.stopped;
      _currentUrl = null;
      _audioTracks = [];
      notifyListeners();
    } catch (e) {
      debugPrint('[VLC] Stop error: $e');
    }
  }

  /// Pause playback
  Future<void> pause() async {
    if (!_initialized) return;

    try {
      await _channel.invokeMethod('pause');
    } catch (e) {
      debugPrint('[VLC] Pause error: $e');
    }
  }

  /// Resume playback (toggle pause)
  Future<void> resume() async {
    if (!_initialized) return;

    try {
      await _channel.invokeMethod('pause'); // VLC pause toggles
    } catch (e) {
      debugPrint('[VLC] Resume error: $e');
    }
  }

  /// Set volume (0-200) - VLC-style 2x amplification
  /// Values >100 enable software amplification (may cause distortion)
  Future<void> setVolume(int volume) async {
    if (!_initialized) return;

    try {
      // CRITICAL: Allow 0-200 for VLC-style 2x volume boost
      final vol = volume.clamp(0, 200);
      debugPrint('[VLC] SetVolume: requesting $vol%');
      await _channel.invokeMethod('setVolume', {'volume': vol});
      _volume = vol;

      // Verify the volume was actually applied
      final applied = await _channel.invokeMethod<int>('getVolume');
      debugPrint('[VLC] SetVolume: applied = $applied% (requested $vol%)');

      notifyListeners();
    } catch (e) {
      debugPrint('[VLC] SetVolume error: $e');
    }
  }

  /// Set mute state
  Future<void> setMute(bool mute) async {
    if (!_initialized) return;

    try {
      await _channel.invokeMethod('setMute', {'mute': mute});
      _isMuted = mute;
      notifyListeners();
    } catch (e) {
      debugPrint('[VLC] SetMute error: $e');
    }
  }

  /// Toggle mute
  Future<void> toggleMute() async {
    await setMute(!_isMuted);
  }

  /// Get current volume from VLC
  Future<int> getVolume() async {
    if (!_initialized) return 0;

    try {
      final vol = await _channel.invokeMethod<int>('getVolume');
      _volume = vol ?? 0;
      return _volume;
    } catch (e) {
      debugPrint('[VLC] GetVolume error: $e');
      return _volume;
    }
  }

  /// Refresh audio tracks from VLC
  Future<void> refreshAudioTracks() async {
    if (!_initialized) return;

    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('getAudioTracks');
      if (result != null) {
        _audioTracks = result.map((track) {
          final map = Map<String, dynamic>.from(track as Map);
          return VlcAudioTrack(
            id: map['id'] as int,
            name: map['name'] as String? ?? 'Track ${map['id']}',
          );
        }).toList();

        // Get current track
        final currentId = await _channel.invokeMethod<int>('getAudioTrack');
        _currentAudioTrack = currentId ?? -1;

        debugPrint(
            '[VLC] Audio tracks: $_audioTracks (current: $_currentAudioTrack)');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[VLC] RefreshAudioTracks error: $e');
    }
  }

  /// Set audio track
  Future<void> setAudioTrack(int trackId) async {
    if (!_initialized) return;

    try {
      debugPrint('[VLC] Setting audio track: $trackId');
      await _channel.invokeMethod('setAudioTrack', {'trackId': trackId});
      _currentAudioTrack = trackId;
      notifyListeners();
    } catch (e) {
      debugPrint('[VLC] SetAudioTrack error: $e');
    }
  }

  /// Check if currently playing
  Future<bool> checkIsPlaying() async {
    if (!_initialized) return false;

    try {
      final playing = await _channel.invokeMethod<bool>('isPlaying');
      _isPlaying = playing ?? false;
      return _isPlaying;
    } catch (e) {
      debugPrint('[VLC] IsPlaying error: $e');
      return false;
    }
  }

  /// Get texture ID for video rendering
  Future<int> getTextureId() async {
    if (!_initialized) return -1;

    try {
      final id = await _channel.invokeMethod<int>('getTextureId');
      _textureId = id ?? -1;
      return _textureId;
    } catch (e) {
      debugPrint('[VLC] GetTextureId error: $e');
      return -1;
    }
  }

  /// Attach native child window for video rendering.
  /// If width or height are 0, the video will occupy the full client area.
  Future<bool> attachVideo(
      {int x = 0, int y = 0, int width = 0, int height = 0}) async {
    if (!_initialized) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('attachVideo', {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      });
      return ok == true;
    } catch (e) {
      debugPrint('[VLC] AttachVideo error: $e');
      return false;
    }
  }

  /// Update video bounds of the native child HWND.
  Future<void> setVideoBounds(int x, int y, int width, int height) async {
    if (!_initialized) return;
    try {
      await _channel.invokeMethod('setVideoBounds', {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      });
    } catch (e) {
      debugPrint('[VLC] SetVideoBounds error: $e');
    }
  }

  /// Detach and destroy native child HWND
  Future<void> detachVideo() async {
    if (!_initialized) return;
    try {
      await _channel.invokeMethod('detachVideo');
    } catch (e) {
      debugPrint('[VLC] DetachVideo error: $e');
    }
  }

  /// Hide video HWND temporarily (for dialogs)
  Future<void> hideVideo() async {
    if (!_initialized) return;
    try {
      await _channel.invokeMethod('hideVideo');
      debugPrint('[VLC] hideVideo called');
    } catch (e) {
      debugPrint('[VLC] HideVideo error: $e');
    }
  }

  /// Show video HWND (after dialogs close)
  Future<void> showVideo() async {
    if (!_initialized) return;
    try {
      await _channel.invokeMethod('showVideo');
      debugPrint('[VLC] showVideo called');
    } catch (e) {
      debugPrint('[VLC] ShowVideo error: $e');
    }
  }

  /// Dispose VLC resources
  Future<void> dispose() async {
    debugPrint('[VLC] Disposing');

    _eventSubscription?.cancel();
    _eventSubscription = null;

    if (_initialized) {
      try {
        await _channel.invokeMethod('dispose');
      } catch (e) {
        debugPrint('[VLC] Dispose error: $e');
      }
    }

    _initialized = false;
    _isPlaying = false;
    _state = VlcState.idle;
    _audioTracks = [];
    _currentUrl = null;

    super.dispose();
  }
}

/// Singleton instance for global access
class VlcPlayer {
  static VlcPlayerController? _instance;

  static VlcPlayerController get instance {
    _instance ??= VlcPlayerController();
    return _instance!;
  }

  static Future<void> disposeInstance() async {
    if (_instance != null) {
      await _instance!.dispose();
      _instance = null;
    }
  }
}
