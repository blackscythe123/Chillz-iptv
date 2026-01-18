// Player Engine - Abstract interface for platform-specific video players
// Supports Windows (libVLC) and Android (media_kit/MPV)

import 'dart:async';
import 'package:flutter/widgets.dart';

/// Unified player state across all platforms
enum PlayerState {
  idle,
  loading,
  buffering,
  playing,
  paused,
  stopped,
  ended,
  error,
}

/// Player error with HTTP status inference
class PlayerError {
  final String message;
  final int? httpStatusCode; // 403, 404, etc. if detectable
  final bool isRecoverable;
  final DateTime timestamp;

  PlayerError({
    required this.message,
    this.httpStatusCode,
    this.isRecoverable = true,
  }) : timestamp = DateTime.now();

  bool get isForbidden => httpStatusCode == 403;
  bool get isNotFound => httpStatusCode == 404;
  bool get isNetworkError =>
      message.toLowerCase().contains('network') ||
      message.toLowerCase().contains('connection');

  @override
  String toString() =>
      'PlayerError($message, http=$httpStatusCode, recoverable=$isRecoverable)';
}

/// Audio track information
class AudioTrack {
  final int id;
  final String name;
  final String? language;

  AudioTrack({required this.id, required this.name, this.language});

  @override
  String toString() => 'AudioTrack($id: $name)';
}

/// Abstract player engine interface
/// All platform-specific players must implement this
abstract class PlayerEngine extends ChangeNotifier {
  // ============== State Getters ==============

  /// Current playback state
  PlayerState get state;

  /// Whether the player is initialized and ready
  bool get isInitialized;

  /// Whether media is currently playing
  bool get isPlaying;

  /// Current volume (0-100, can go up to 200 for boost)
  int get volume;

  /// Whether audio is muted
  bool get isMuted;

  /// Available audio tracks
  List<AudioTrack> get audioTracks;

  /// Current audio track ID (-1 if none)
  int get currentAudioTrack;

  /// Current media URL
  String? get currentUrl;

  /// Last error message
  String? get lastError;

  /// Video dimensions (0 if not available)
  int get videoWidth;
  int get videoHeight;

  // ============== Streams ==============

  /// Stream of player state changes
  Stream<PlayerState> get stateStream;

  /// Stream of player errors
  Stream<PlayerError> get errorStream;

  // ============== Lifecycle ==============

  /// Initialize the player engine
  /// Must be called before any playback
  Future<bool> init();

  /// Dispose and release all resources
  /// Call when player is no longer needed
  @override
  Future<void> dispose();

  // ============== Playback Control ==============

  /// Play media from URL (HLS, IPTV, etc.)
  Future<bool> play(String url);

  /// Stop playback and release media
  Future<void> stop();

  /// Pause playback
  Future<void> pause();

  /// Resume playback from paused state
  Future<void> resume();

  // ============== Volume Control ==============

  /// Set volume (0-200, values >100 enable boost)
  Future<void> setVolume(double vol);

  /// Toggle mute state
  Future<void> toggleMute();

  // ============== Audio Tracks ==============

  /// Set active audio track by ID
  Future<void> setAudioTrack(int trackId);

  /// Refresh available audio tracks
  Future<void> refreshAudioTracks();

  // ============== Video Rendering ==============

  /// Build the video widget for this platform
  /// Returns a widget that displays the video
  Widget buildVideoWidget({
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
  });

  // ============== Platform-Specific ==============

  /// Update video bounds (Windows only - for HWND positioning)
  Future<void> setVideoBounds(int x, int y, int width, int height) async {}

  /// Attach video to render target (Windows only)
  Future<bool> attachVideo({int width = 0, int height = 0}) async => true;
}
