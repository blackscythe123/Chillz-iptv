// Windows VLC Player - Wrapper around existing VlcPlayerController
// Implements PlayerEngine interface for Windows platform
// NO modifications to native code - purely wraps Dart service

import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';

import 'player_engine.dart';
import '../services/vlc_player_service.dart';

/// Windows-specific player using libVLC via platform channels
class WindowsVlcPlayer extends PlayerEngine {
  final VlcPlayerController _vlc = VlcPlayerController();

  // Stream controllers
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerError> _errorController =
      StreamController<PlayerError>.broadcast();

  // Track state changes from VLC
  PlayerState _lastEmittedState = PlayerState.idle;

  WindowsVlcPlayer() {
    // Listen to VLC state changes and map to PlayerState
    _vlc.addListener(_onVlcStateChanged);
  }

  void _onVlcStateChanged() {
    final newState = _mapVlcState(_vlc.state);
    if (newState != _lastEmittedState) {
      _lastEmittedState = newState;
      _stateController.add(newState);
    }

    // Emit errors
    if (_vlc.lastError != null && _vlc.state == VlcState.error) {
      _errorController.add(_parseError(_vlc.lastError!));
    }

    notifyListeners();
  }

  PlayerState _mapVlcState(VlcState vlcState) {
    switch (vlcState) {
      case VlcState.idle:
        return PlayerState.idle;
      case VlcState.opening:
        return PlayerState.loading;
      case VlcState.buffering:
        return PlayerState.buffering;
      case VlcState.playing:
        return PlayerState.playing;
      case VlcState.paused:
        return PlayerState.paused;
      case VlcState.stopped:
        return PlayerState.stopped;
      case VlcState.ended:
        return PlayerState.ended;
      case VlcState.error:
        return PlayerState.error;
    }
  }

  PlayerError _parseError(String errorMessage) {
    int? httpCode;
    bool recoverable = true;

    // Try to infer HTTP status from error message
    final msg = errorMessage.toLowerCase();
    if (msg.contains('403') || msg.contains('forbidden')) {
      httpCode = 403;
      recoverable = false;
    } else if (msg.contains('404') || msg.contains('not found')) {
      httpCode = 404;
      recoverable = false;
    } else if (msg.contains('401') || msg.contains('unauthorized')) {
      httpCode = 401;
      recoverable = false;
    } else if (msg.contains('timeout') || msg.contains('network')) {
      recoverable = true;
    }

    return PlayerError(
      message: errorMessage,
      httpStatusCode: httpCode,
      isRecoverable: recoverable,
    );
  }

  // ============== State Getters ==============

  @override
  PlayerState get state => _mapVlcState(_vlc.state);

  @override
  bool get isInitialized => _vlc.initialized;

  @override
  bool get isPlaying => _vlc.isPlaying;

  @override
  int get volume => _vlc.volume;

  @override
  bool get isMuted => _vlc.isMuted;

  @override
  List<AudioTrack> get audioTracks =>
      _vlc.audioTracks.map((t) => AudioTrack(id: t.id, name: t.name)).toList();

  @override
  int get currentAudioTrack => _vlc.currentAudioTrack;

  @override
  String? get currentUrl => _vlc.currentUrl;

  @override
  String? get lastError => _vlc.lastError;

  @override
  int get videoWidth => _vlc.videoWidth;

  @override
  int get videoHeight => _vlc.videoHeight;

  // ============== Streams ==============

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  @override
  Stream<PlayerError> get errorStream => _errorController.stream;

  // ============== Lifecycle ==============

  @override
  Future<bool> init() async {
    if (_vlc.initialized) return true;

    // Get plugins path for Windows
    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;
    final pluginsPath = '$exeDir\\plugins';

    return await _vlc.initialize(pluginsPath: pluginsPath);
  }

  @override
  Future<void> dispose() async {
    _vlc.removeListener(_onVlcStateChanged);
    await _vlc.dispose();
    await _stateController.close();
    await _errorController.close();
    super.dispose();
  }

  // ============== Playback Control ==============

  @override
  Future<bool> play(String url) async {
    return await _vlc.play(url);
  }

  @override
  Future<void> stop() async {
    await _vlc.stop();
  }

  @override
  Future<void> pause() async {
    await _vlc.pause();
  }

  @override
  Future<void> resume() async {
    await _vlc.resume();
  }

  // ============== Volume Control ==============

  @override
  Future<void> setVolume(double vol) async {
    await _vlc.setVolume(vol.round());
  }

  @override
  Future<void> toggleMute() async {
    await _vlc.toggleMute();
  }

  // ============== Audio Tracks ==============

  @override
  Future<void> setAudioTrack(int trackId) async {
    await _vlc.setAudioTrack(trackId);
  }

  @override
  Future<void> refreshAudioTracks() async {
    await _vlc.refreshAudioTracks();
  }

  // ============== Video Rendering ==============

  @override
  Widget buildVideoWidget({
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
  }) {
    // Windows uses native HWND rendering - return placeholder
    // The actual video is rendered by the native VLC child window
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF000000),
      child: const Center(
        child: Text(
          'VLC Native Surface',
          style: TextStyle(color: Color(0x55FFFFFF), fontSize: 12),
        ),
      ),
    );
  }

  // ============== Windows-Specific ==============

  @override
  Future<void> setVideoBounds(int x, int y, int width, int height) async {
    await _vlc.setVideoBounds(x, y, width, height);
  }

  @override
  Future<bool> attachVideo({int width = 0, int height = 0}) async {
    return await _vlc.attachVideo(width: width, height: height);
  }

  /// Hide video HWND (for dialogs)
  Future<void> hideVideo() async {
    await _vlc.hideVideo();
  }

  /// Show video HWND
  Future<void> showVideo() async {
    await _vlc.showVideo();
  }
}
