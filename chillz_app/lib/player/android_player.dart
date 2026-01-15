// Android MPV Player - media_kit implementation
// Implements PlayerEngine interface for Android platform
// Supports ARM64, x86_64, and Android TV

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import 'player_engine.dart' as engine;

/// Android-specific player using media_kit (MPV backend)
class AndroidMpvPlayer extends engine.PlayerEngine {
  late final mk.Player _player;
  late final VideoController _videoController;

  // Stream controllers
  final StreamController<engine.PlayerState> _stateController =
      StreamController<engine.PlayerState>.broadcast();
  final StreamController<engine.PlayerError> _errorController =
      StreamController<engine.PlayerError>.broadcast();

  // State
  engine.PlayerState _state = engine.PlayerState.idle;
  bool _initialized = false;
  bool _isPlaying = false;
  int _volume = 100;
  bool _isMuted = false;
  List<engine.AudioTrack> _audioTracks = [];
  int _currentAudioTrack = -1;
  String? _currentUrl;
  String? _lastError;
  int _videoWidth = 0;
  int _videoHeight = 0;

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  // Reconnection logic
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  Timer? _reconnectTimer;

  AndroidMpvPlayer() {
    _player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        // Enable buffering for IPTV streams
        bufferSize: 32 * 1024 * 1024, // 32MB buffer
        logLevel: mk.MPVLogLevel.warn,
      ),
    );

    _videoController = VideoController(_player);
  }

  // ============== State Getters ==============

  @override
  engine.PlayerState get state => _state;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isPlaying => _isPlaying;

  @override
  int get volume => _volume;

  @override
  bool get isMuted => _isMuted;

  @override
  List<engine.AudioTrack> get audioTracks => _audioTracks;

  @override
  int get currentAudioTrack => _currentAudioTrack;

  @override
  String? get currentUrl => _currentUrl;

  @override
  String? get lastError => _lastError;

  @override
  int get videoWidth => _videoWidth;

  @override
  int get videoHeight => _videoHeight;

  // ============== Streams ==============

  @override
  Stream<engine.PlayerState> get stateStream => _stateController.stream;

  @override
  Stream<engine.PlayerError> get errorStream => _errorController.stream;

  // ============== Lifecycle ==============

  @override
  Future<bool> init() async {
    if (_initialized) return true;

    try {
      debugPrint('[AndroidMPV] Initializing media_kit player');

      // Subscribe to player streams
      _subscriptions.add(
        _player.stream.playing.listen((playing) {
          _isPlaying = playing;
          if (playing) {
            _updateState(engine.PlayerState.playing);
            _reconnectAttempts = 0; // Reset on successful play
          }
          notifyListeners();
        }),
      );

      _subscriptions.add(
        _player.stream.buffering.listen((buffering) {
          if (buffering) {
            _updateState(engine.PlayerState.buffering);
          } else if (_isPlaying) {
            _updateState(engine.PlayerState.playing);
          }
        }),
      );

      _subscriptions.add(
        _player.stream.completed.listen((completed) {
          if (completed) {
            _updateState(engine.PlayerState.ended);
          }
        }),
      );

      _subscriptions.add(
        _player.stream.error.listen((error) {
          _handleError(error);
        }),
      );

      _subscriptions.add(
        _player.stream.width.listen((w) {
          _videoWidth = w ?? 0;
          notifyListeners();
        }),
      );

      _subscriptions.add(
        _player.stream.height.listen((h) {
          _videoHeight = h ?? 0;
          notifyListeners();
        }),
      );

      _subscriptions.add(
        _player.stream.volume.listen((v) {
          _volume = v.round();
          notifyListeners();
        }),
      );

      _subscriptions.add(
        _player.stream.tracks.listen((tracks) {
          _updateAudioTracks(tracks);
        }),
      );

      _subscriptions.add(
        _player.stream.log.listen((log) {
          // Parse MPV logs for HTTP errors
          _parseLogForErrors(log.text);
        }),
      );

      _initialized = true;
      debugPrint('[AndroidMPV] Initialized successfully');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[AndroidMPV] Init error: $e');
      _lastError = e.toString();
      return false;
    }
  }

  void _updateState(engine.PlayerState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
      notifyListeners();
    }
  }

  void _handleError(String error) {
    debugPrint('[AndroidMPV] Error: $error');
    _lastError = error;

    final playerError = _parseError(error);
    _errorController.add(playerError);

    // Attempt reconnection for recoverable errors
    if (playerError.isRecoverable &&
        _reconnectAttempts < _maxReconnectAttempts) {
      _scheduleReconnect();
    } else {
      _updateState(engine.PlayerState.error);
    }

    notifyListeners();
  }

  void _scheduleReconnect() {
    if (_currentUrl == null) return;

    _reconnectTimer?.cancel();
    _reconnectAttempts++;

    final delay = Duration(seconds: _reconnectAttempts * 2);
    debugPrint(
        '[AndroidMPV] Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s');

    _reconnectTimer = Timer(delay, () async {
      if (_currentUrl != null) {
        debugPrint('[AndroidMPV] Attempting reconnect...');
        await play(_currentUrl!);
      }
    });
  }

  engine.PlayerError _parseError(String errorMessage) {
    int? httpCode;
    bool recoverable = true;

    final msg = errorMessage.toLowerCase();

    // HTTP error detection from MPV
    if (msg.contains('403') ||
        msg.contains('forbidden') ||
        msg.contains('access denied')) {
      httpCode = 403;
      recoverable = false;
    } else if (msg.contains('404') ||
        msg.contains('not found') ||
        msg.contains('no such file')) {
      httpCode = 404;
      recoverable = false;
    } else if (msg.contains('401') || msg.contains('unauthorized')) {
      httpCode = 401;
      recoverable = false;
    } else if (msg.contains('500') || msg.contains('internal server')) {
      httpCode = 500;
      recoverable = true;
    } else if (msg.contains('503') || msg.contains('service unavailable')) {
      httpCode = 503;
      recoverable = true;
    } else if (msg.contains('timeout') || msg.contains('timed out')) {
      recoverable = true;
    } else if (msg.contains('network') || msg.contains('connection')) {
      recoverable = true;
    } else if (msg.contains('eof') || msg.contains('end of file')) {
      recoverable = true;
    }

    return engine.PlayerError(
      message: errorMessage,
      httpStatusCode: httpCode,
      isRecoverable: recoverable,
    );
  }

  void _parseLogForErrors(String log) {
    final lower = log.toLowerCase();

    // Detect HTTP errors from MPV demuxer logs
    if (lower.contains('http error 403') ||
        lower.contains('server returned 403')) {
      _errorController.add(engine.PlayerError(
        message: 'Stream forbidden (HTTP 403)',
        httpStatusCode: 403,
        isRecoverable: false,
      ));
    } else if (lower.contains('http error 404') ||
        lower.contains('server returned 404')) {
      _errorController.add(engine.PlayerError(
        message: 'Stream not found (HTTP 404)',
        httpStatusCode: 404,
        isRecoverable: false,
      ));
    }
  }

  void _updateAudioTracks(mk.Tracks tracks) {
    _audioTracks = tracks.audio
        .map((t) => engine.AudioTrack(
              id: int.tryParse(t.id) ?? 0,
              name: t.title ?? t.language ?? 'Track ${t.id}',
              language: t.language,
            ))
        .toList();

    // Find current track
    final currentTrack = tracks.audio
        .where((t) => t.id == _player.state.track.audio.id)
        .firstOrNull;
    _currentAudioTrack =
        currentTrack != null ? (int.tryParse(currentTrack.id) ?? -1) : -1;

    debugPrint(
        '[AndroidMPV] Audio tracks: ${_audioTracks.length}, current: $_currentAudioTrack');
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    debugPrint('[AndroidMPV] Disposing');

    _reconnectTimer?.cancel();

    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    await _player.dispose();
    await _stateController.close();
    await _errorController.close();

    _initialized = false;
    super.dispose();
  }

  // ============== Playback Control ==============

  @override
  Future<bool> play(String url) async {
    if (!_initialized) {
      final initOk = await init();
      if (!initOk) return false;
    }

    try {
      debugPrint('[AndroidMPV] Playing: $url');
      _currentUrl = url;
      _lastError = null;
      _updateState(engine.PlayerState.loading);

      await _player.open(mk.Media(url));

      // Apply current volume
      await _player.setVolume(_volume.toDouble());

      return true;
    } catch (e) {
      debugPrint('[AndroidMPV] Play error: $e');
      _lastError = e.toString();
      _updateState(engine.PlayerState.error);
      return false;
    }
  }

  @override
  Future<void> stop() async {
    debugPrint('[AndroidMPV] Stopping');
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;

    await _player.stop();
    _currentUrl = null;
    _updateState(engine.PlayerState.stopped);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _updateState(engine.PlayerState.paused);
  }

  @override
  Future<void> resume() async {
    await _player.play();
  }

  // ============== Volume Control ==============

  @override
  Future<void> setVolume(double vol) async {
    final clampedVol = vol.clamp(0.0, 200.0);
    await _player.setVolume(clampedVol);
    _volume = clampedVol.round();
    notifyListeners();
  }

  @override
  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    if (_isMuted) {
      await _player.setVolume(0);
    } else {
      await _player.setVolume(_volume.toDouble());
    }
    notifyListeners();
  }

  // ============== Audio Tracks ==============

  @override
  Future<void> setAudioTrack(int trackId) async {
    final tracks = _player.state.tracks.audio;
    final track =
        tracks.where((t) => int.tryParse(t.id) == trackId).firstOrNull;

    if (track != null) {
      await _player.setAudioTrack(track);
      _currentAudioTrack = trackId;
      notifyListeners();
    }
  }

  @override
  Future<void> refreshAudioTracks() async {
    _updateAudioTracks(_player.state.tracks);
  }

  // ============== Video Rendering ==============

  @override
  Widget buildVideoWidget({
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
  }) {
    return Video(
      controller: _videoController,
      width: width,
      height: height,
      fit: fit,
      controls: _noVideoControls, // We use custom controls
    );
  }

  /// Get the video controller for custom rendering
  VideoController get videoController => _videoController;
}

/// No controls - we use custom UI
Widget _noVideoControls(VideoState state) {
  return const SizedBox.shrink();
}
