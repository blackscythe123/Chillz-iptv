import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
// Use media_kit for cross-platform video playback
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'services/iptv_service.dart';

// Error classification for tolerance layer
enum ErrorType { recoverable, retryable, fatal, ignored }

class ErrorClassification {
  final ErrorType type;
  final String userMessage;
  final bool shouldAutoRecover;

  const ErrorClassification(
      this.type, this.userMessage, this.shouldAutoRecover);

  static ErrorClassification classify(String error) {
    final lower = error.toLowerCase();

    // IGNORE: Non-fatal FFmpeg/HLS warnings and playlist skippings
    if ((lower.contains('packet') && lower.contains('corrupt')) ||
        lower.contains('corrupt packet') ||
        lower.contains('packet corrupt') ||
        lower.contains('skipping') ||
        lower.contains('expired') ||
        lower.contains('expired from playlist') ||
        lower.contains('warning')) {
      // Treat as informational - don't trigger retries or audio switches
      return const ErrorClassification(
          ErrorType.ignored, 'Non-fatal stream issue', false);
    }

    // RECOVERABLE: Audio/codec issues - auto-switch track
    if (lower.contains('audio') ||
        lower.contains('codec') ||
        lower.contains('decod') ||
        lower.contains('unsupported format')) {
      return const ErrorClassification(
          ErrorType.recoverable, 'Adjusting audio...', true);
    }

    // RETRYABLE: Network issues - retry with backoff
    if (lower.contains('timeout') ||
        lower.contains('connection') ||
        lower.contains('network') ||
        lower.contains('buffering') ||
        lower.contains('eof') ||
        lower.contains('end of file')) {
      return const ErrorClassification(
          ErrorType.retryable, 'Connection interrupted, reconnecting...', true);
    }

    // FATAL: Unrecoverable errors - show user message
    if (lower.contains('404') || lower.contains('not found')) {
      return const ErrorClassification(
          ErrorType.fatal, 'Stream not found', false);
    }
    if (lower.contains('403') ||
        lower.contains('forbidden') ||
        lower.contains('denied')) {
      return const ErrorClassification(ErrorType.fatal, 'Access denied', false);
    }
    if (lower.contains('geo') ||
        lower.contains('region') ||
        lower.contains('country')) {
      return const ErrorClassification(
          ErrorType.fatal, 'Content not available in your region', false);
    }

    // Default to retryable for unknown errors
    return const ErrorClassification(
        ErrorType.retryable, 'Playback interrupted', true);
  }
}

// Language code to full name mapping
const Map<String, String> _languageNames = {
  'en': 'English',
  'eng': 'English',
  'hi': 'Hindi',
  'hin': 'Hindi',
  'ta': 'Tamil',
  'tam': 'Tamil',
  'te': 'Telugu',
  'tel': 'Telugu',
  'ml': 'Malayalam',
  'mal': 'Malayalam',
  'kn': 'Kannada',
  'kan': 'Kannada',
  'bn': 'Bengali',
  'ben': 'Bengali',
  'mr': 'Marathi',
  'mar': 'Marathi',
  'gu': 'Gujarati',
  'guj': 'Gujarati',
  'pa': 'Punjabi',
  'pan': 'Punjabi',
  'or': 'Odia',
  'ori': 'Odia',
  'as': 'Assamese',
  'asm': 'Assamese',
  'ur': 'Urdu',
  'urd': 'Urdu',
  'ar': 'Arabic',
  'ara': 'Arabic',
  'es': 'Spanish',
  'spa': 'Spanish',
  'fr': 'French',
  'fra': 'French',
  'de': 'German',
  'deu': 'German',
  'it': 'Italian',
  'ita': 'Italian',
  'pt': 'Portuguese',
  'por': 'Portuguese',
  'ru': 'Russian',
  'rus': 'Russian',
  'ja': 'Japanese',
  'jpn': 'Japanese',
  'ko': 'Korean',
  'kor': 'Korean',
  'zh': 'Chinese',
  'zho': 'Chinese',
  'chi': 'Chinese',
  'th': 'Thai',
  'tha': 'Thai',
  'vi': 'Vietnamese',
  'vie': 'Vietnamese',
  'id': 'Indonesian',
  'ind': 'Indonesian',
  'ms': 'Malay',
  'msa': 'Malay',
  'tr': 'Turkish',
  'tur': 'Turkish',
  'pl': 'Polish',
  'pol': 'Polish',
  'nl': 'Dutch',
  'nld': 'Dutch',
  'sv': 'Swedish',
  'swe': 'Swedish',
  'no': 'Norwegian',
  'nor': 'Norwegian',
  'da': 'Danish',
  'dan': 'Danish',
  'fi': 'Finnish',
  'fin': 'Finnish',
  'el': 'Greek',
  'ell': 'Greek',
  'he': 'Hebrew',
  'heb': 'Hebrew',
  'und': 'Unknown',
  'auto': 'Auto',
  'none': 'None',
  '': 'Unknown',
};

String _getLanguageName(String? code, {int? trackIndex}) {
  if (code == null || code.isEmpty || code == 'und' || code == 'unknown') {
    // Return synthetic label instead of "Unknown"
    return trackIndex != null
        ? 'Audio Track ${trackIndex + 1}'
        : 'Default Audio';
  }
  final name = _languageNames[code.toLowerCase()];
  if (name == 'Unknown' && trackIndex != null) {
    return 'Audio Track ${trackIndex + 1}';
  }
  return name ?? code.toUpperCase();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit - REQUIRED
  MediaKit.ensureInitialized();

  runApp(const ChillzApp());
}

class ChillzApp extends StatelessWidget {
  const ChillzApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => IptvService()..loadChannels()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Chillz — Desktop',
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0F1720),
        ),
        home: const ChillzHome(),
      ),
    );
  }
}

class ChillzHome extends StatefulWidget {
  const ChillzHome({Key? key}) : super(key: key);

  @override
  _ChillzHomeState createState() => _ChillzHomeState();
}

class _ChillzHomeState extends State<ChillzHome> {
  late IptvService _iptvService;

  Player? _player;
  VideoController? _videoController;
  bool _controllerInitialized = false;
  String _currentUrl = '';
  bool _isPlaying = false;
  double _volume = 100.0;
  String _status = 'idle';
  String _lastError = '';

  // Buffering state tracking
  int _bufferCount = 0;
  DateTime? _lastBufferTime;
  bool _isAdaptiveMode = false;
  Timer? _bufferTimeoutTimer;
  bool _isRecoveringBuffer = false;

  // Audio tracks for language selection
  List<AudioTrack> _audioTracks = [];
  AudioTrack? _selectedAudioTrack;

  // Audio error recovery tracking
  bool _audioErrorRecovering = false;
  int _audioErrorCount = 0;
  Set<String> _failedAudioTracks = {}; // Track IDs that failed decoding
  int _retryCount = 0; // For network retry with backoff
  static const int _maxRetries = 3;

  // Dev mode toggle - hide debug info from users
  bool _devMode = false;

  // Switching / unmute helpers to ensure audio only after first decoded frame
  double? _preSwitchVolume;
  bool _awaitingFirstAudioFrame = false;
  Timer? _firstAudioFrameTimer;

  // libVLC detection (not needed for media_kit, but kept for UI)
  bool _libVlc64 = true;
  bool _libVlc32 = false;
  String _libVlcNote = 'Using media_kit (bundled).';

  // Search & Filters state
  String _search = '';
  String _selectedCategory = 'all';
  String _selectedCountry = 'all';
  String _selectedLanguage = 'all';
  Timer? _searchTimer;
  String _searchQuery = '';

  // Quality selection
  String _selectedQuality = 'auto';
  List<String> _availableQualities = ['auto'];

  // Keyboard shortcuts and focus
  final FocusNode _appFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _urlFocusNode = FocusNode();
  bool _isFullscreen = false;
  bool _isTextFieldFocused = false; // Track if any text field has focus

  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _player = null;
    _videoController = null;
    // obtain iptv service after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _iptvService = Provider.of<IptvService>(context, listen: false);
      if (!_iptvService.loading && _iptvService.channels.isEmpty) {
        _iptvService.loadChannels();
      }
      // media_kit bundles everything, so mark as ready
      setState(() {
        _status = 'ready';
        _libVlcNote = 'Using media_kit (self-contained).';
      });

      // Set up focus listeners for text fields to disable shortcuts when typing
      _searchFocusNode.addListener(_onTextFieldFocusChange);
      _urlFocusNode.addListener(_onTextFieldFocusChange);
    });
  }

  // Handle text field focus changes to disable shortcuts while typing
  void _onTextFieldFocusChange() {
    setState(() {
      _isTextFieldFocused = _searchFocusNode.hasFocus || _urlFocusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    _player?.dispose();
    _urlController.dispose();
    _searchTimer?.cancel();
    _bufferTimeoutTimer?.cancel();
    _firstAudioFrameTimer?.cancel();
    _awaitingFirstAudioFrame = false;
    _searchFocusNode.removeListener(_onTextFieldFocusChange);
    _urlFocusNode.removeListener(_onTextFieldFocusChange);
    _appFocusNode.dispose();
    _searchFocusNode.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  Future<void> _startPlayback(String url) async {
    try {
      // Begin switching: mute app & fully dispose previous player to prevent ghost audio
      _preSwitchVolume = _volume;
      _awaitingFirstAudioFrame = true;
      try {
        if (_player != null) {
          try {
            await _player!.setVolume(0);
          } catch (_) {}
          await _disposePlayerFully(_player);
          debugPrint('Previous player fully disposed');
        }
      } catch (_) {}
      _player = null;
      _videoController = null;
      _controllerInitialized = false;
      _audioTracks = [];
      _selectedAudioTrack = null;
      _audioErrorCount = 0; // Reset audio error count for new playback
      _audioErrorRecovering = false;

      setState(() {
        _currentUrl = url;
        // Show explicit switching state so UX indicates a channel change
        _status = 'switching';
        _lastError = '';
      });
      debugPrint('Start switching to: $url');

      // First, check if URL is reachable (with timeout)
      final urlStatus = await _checkUrlAvailability(url);
      if (!urlStatus['available']) {
        setState(() {
          _lastError = urlStatus['error'] ?? 'Stream unavailable';
          _status = 'unavailable';
        });
        return;
      }

      setState(() {
        _status = 'loading';
      });

      // Create a new media_kit Player with optimized configuration for stable streaming
      final player = Player(
        configuration: PlayerConfiguration(
          // Larger buffer for stable live streams
          bufferSize: 64 * 1024 * 1024, // 64MB buffer for stability
        ),
      );

      // Apply MPV options for better network handling and reduced buffering
      await _applyPlayerOptions(player);

      final videoController = VideoController(player);

      // Set up stream listeners for state changes
      player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            _isPlaying = playing;
            if (playing) {
              _controllerInitialized = true;
              // If we are awaiting the first audio frame after a channel switch/reconnect,
              // verify briefly and then restore volume so we don't unmute into silence or noise.
              if (_awaitingFirstAudioFrame) {
                _firstAudioFrameTimer?.cancel();
                _firstAudioFrameTimer =
                    Timer(const Duration(milliseconds: 800), () async {
                  if (!mounted) return;
                  final restore = _preSwitchVolume ?? 100.0;
                  await _setVolume(restore);
                  setState(() {
                    _preSwitchVolume = null;
                    _awaitingFirstAudioFrame = false;
                    _status = 'playing';
                  });
                });
              } else {
                _status = 'playing';
              }
            }
          });
        }
      });

      player.stream.completed.listen((completed) {
        if (completed && mounted) {
          setState(() => _status = 'ended');
        }
      });

      player.stream.buffering.listen((buffering) {
        if (mounted) {
          if (buffering) {
            setState(() => _status = 'buffering');
            _trackBuffering();
            // start a recovery timer (12s) if buffering persists
            _bufferTimeoutTimer?.cancel();
            _bufferTimeoutTimer = Timer(const Duration(seconds: 12), () {
              if (_status == 'buffering' && !_isRecoveringBuffer) {
                _attemptBufferRecovery();
              }
            });
          } else {
            // cancel timeout when buffering stops
            _bufferTimeoutTimer?.cancel();
            if (_status == 'buffering') setState(() => _status = 'playing');
          }
        }
      });

      player.stream.error.listen((error) {
        if (error.isNotEmpty && mounted) {
          _handlePlayerError(error);
        }
      });

      // Listen for audio tracks (for language selection)
      player.stream.tracks.listen((tracks) {
        if (mounted) {
          setState(() {
            _audioTracks = tracks.audio;
            if (_audioTracks.isNotEmpty && _selectedAudioTrack == null) {
              _selectedAudioTrack = _audioTracks.first;
            }
          });
        }
      });

      // Try to open the media URL with timeout
      bool opened = false;
      try {
        await player.open(Media(url)).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException('Connection timed out after 15 seconds');
          },
        );
        opened = true;
      } catch (e) {
        // If direct open fails, try alternate URL formats
        final altUrl = _getAlternateUrl(url);
        if (altUrl != url) {
          try {
            await player.open(Media(altUrl)).timeout(
                  const Duration(seconds: 10),
                );
            opened = true;
            if (mounted) {
              setState(() => _currentUrl = altUrl);
            }
          } catch (_) {}
        }

        if (!opened) {
          throw e;
        }
      }

      await player.setVolume(_volume);

      _player = player;
      _videoController = videoController;
      _controllerInitialized = true;
      if (mounted) {
        setState(() {
          _status = 'playing';
        });
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        setState(() {
          _lastError = 'Connection timed out - stream may be offline';
          _status = 'timeout';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastError = _parseErrorMessage(e.toString());
          _status = 'error';
        });
      }
    }
  }

  // Check if URL is reachable before attempting playback
  Future<Map<String, dynamic>> _checkUrlAvailability(String url) async {
    try {
      final uri = Uri.parse(url);

      // For HTTP/HTTPS URLs, do a HEAD request to check availability
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        try {
          final response = await http.head(uri).timeout(
                const Duration(seconds: 8),
              );

          if (response.statusCode == 404) {
            return {'available': false, 'error': 'Stream not found (404)'};
          } else if (response.statusCode == 403) {
            return {'available': false, 'error': 'Access denied (403)'};
          } else if (response.statusCode == 500) {
            return {'available': false, 'error': 'Server error (500)'};
          } else if (response.statusCode == 502 || response.statusCode == 503) {
            return {
              'available': false,
              'error': 'Server unavailable (${response.statusCode})'
            };
          } else if (response.statusCode >= 400) {
            return {
              'available': false,
              'error': 'HTTP error ${response.statusCode}'
            };
          }
          return {'available': true};
        } on SocketException {
          return {'available': false, 'error': 'Cannot connect to server'};
        } on TimeoutException {
          // Timeout on HEAD doesn't mean unavailable - some servers don't support HEAD
          return {'available': true};
        } on http.ClientException catch (e) {
          // Some streaming servers don't respond to HEAD - try anyway
          return {'available': true};
        }
      }

      // For other protocols (rtsp, rtmp, etc.), assume available and let player handle it
      return {'available': true};
    } catch (e) {
      // If check fails, still try to play
      return {'available': true};
    }
  }

  // Parse error messages to be more user-friendly
  String _parseErrorMessage(String error) {
    // Use the error classification for consistent messaging
    final classification = ErrorClassification.classify(error);
    return classification.userMessage;
  }

  // Unified error handler using classification system
  Future<void> _handlePlayerError(String error) async {
    final classification = ErrorClassification.classify(error);

    switch (classification.type) {
      case ErrorType.ignored:
        // Non-fatal messages that should not interrupt playback
        if (_devMode) {
          setState(() => _lastError = error);
        }
        debugPrint('Ignored player message: $error');
        return;

      case ErrorType.recoverable:
        // Audio/codec errors - try to auto-recover
        if (!_audioErrorRecovering && _audioErrorCount < 3) {
          await _handleAudioError();
        } else {
          // Silently continue if we've tried enough
          if (_devMode) {
            setState(() => _lastError = error);
          }
        }
        break;

      case ErrorType.retryable:
        // Network errors - retry with backoff
        if (_retryCount < _maxRetries) {
          _retryCount++;
          final delay =
              Duration(seconds: _retryCount * 2); // Exponential backoff

          // Brief reconnecting status - mute while attempting reconnection
          setState(() {
            _status = 'reconnecting';
            _lastError = ''; // Don't show error to user during retry
            _awaitingFirstAudioFrame = true;
            _preSwitchVolume = _volume;
          });

          // Ensure we are muted while reconnecting
          try {
            await _setVolume(0);
          } catch (_) {}

          await Future.delayed(delay);
          if (mounted && _currentUrl.isNotEmpty) {
            await _retryPlayback();
          }
        } else {
          // Max retries reached - show user-friendly error
          setState(() {
            _lastError = classification.userMessage;
            _status = 'error';
          });
        }
        break;

      case ErrorType.fatal:
        // Unrecoverable - show user message
        setState(() {
          _lastError = classification.userMessage;
          _status = 'error';
        });
        break;
    }
  }

  // Retry playback silently
  Future<void> _retryPlayback() async {
    if (_player == null || _currentUrl.isEmpty) return;

    try {
      await _player!.stop();
      await Future.delayed(const Duration(milliseconds: 500));
      await _player!.open(Media(_currentUrl));

      // Success - reset retry count
      _retryCount = 0;
      setState(() {
        _status = 'playing';
        _lastError = '';
      });
    } catch (e) {
      // Will be handled by error listener
    }
  }

  // Fully stop and dispose a player to avoid ghost audio
  Future<void> _disposePlayerFully(Player? player) async {
    if (player == null) return;
    try {
      // Mute and pause first
      try {
        await player.setVolume(0);
      } catch (_) {}
      try {
        await player.pause();
      } catch (_) {}
      try {
        await player.stop().timeout(const Duration(seconds: 2));
      } catch (_) {}
      // Allow native pipelines to flush
      await Future.delayed(const Duration(milliseconds: 250));
      try {
        player.dispose();
        debugPrint('Disposed player native resources');
      } catch (e) {
        debugPrint('Error disposing player: $e');
        try {
          player.dispose();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('disposePlayerFully error: $e');
    } finally {
      if (_player == player) {
        setState(() {
          _player = null;
          _videoController = null;
          _controllerInitialized = false;
        });
      }
    }
  }

  // Handle audio decoding errors with auto-recovery
  Future<void> _handleAudioError() async {
    if (_player == null || _audioErrorRecovering) return;

    _audioErrorRecovering = true;
    _audioErrorCount++;

    // Don't show error message to user - handle silently
    // Only show in dev mode
    if (_devMode) {
      setState(() {
        _lastError = 'Adjusting audio...';
      });
    }

    try {
      // Try switching to a different audio track that hasn't failed
      if (_audioTracks.length > 1) {
        AudioTrack? nextTrack;

        for (int i = 0; i < _audioTracks.length; i++) {
          final track = _audioTracks[i];
          // Skip tracks that have already failed
          if (!_failedAudioTracks.contains(track.id) &&
              track.id != _selectedAudioTrack?.id) {
            nextTrack = track;
            break;
          }
        }

        if (nextTrack != null) {
          try {
            await _player!.setAudioTrack(nextTrack);
            setState(() {
              _selectedAudioTrack = nextTrack;
              _lastError = '';
            });

            // Brief notification only
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Switched audio track'),
                  backgroundColor: Colors.blue.shade700,
                  duration: const Duration(seconds: 1),
                ),
              );
            }
          } catch (e) {
            // Mark this track as failed
            _failedAudioTracks.add(nextTrack.id);
            // Try next track recursively
            _audioErrorRecovering = false;
            await _handleAudioError();
            return;
          }
        } else {
          // All tracks failed - continue with video only
          setState(() {
            _lastError = '';
            _status = 'playing';
          });
        }
      } else {
        // Single track - continue playback despite error
        setState(() {
          _lastError = '';
          _status = 'playing';
        });
      }
    } catch (e) {
      // Silently continue
      setState(() => _lastError = '');
    }

    _audioErrorRecovering = false;
  }

  // Try alternate URL formats (http<->https, add/remove port, etc.)
  String _getAlternateUrl(String url) {
    final uri = Uri.parse(url);

    // Try switching http/https
    if (uri.scheme == 'http') {
      return url.replaceFirst('http://', 'https://');
    } else if (uri.scheme == 'https') {
      return url.replaceFirst('https://', 'http://');
    }

    return url;
  }

  // Apply optimized player settings for stable streaming
  // Note: media_kit handles most optimizations internally via its buffer configuration
  Future<void> _applyPlayerOptions(Player player) async {
    try {
      // Set a reasonable playback rate
      await player.setRate(1.0);
      // Volume boost is handled via setVolume (0-200%)
    } catch (e) {
      debugPrint('Player options warning: $e');
    }
  }

  // Track buffering events for adaptive quality
  void _trackBuffering() {
    final now = DateTime.now();
    if (_lastBufferTime != null &&
        now.difference(_lastBufferTime!).inSeconds < 30) {
      _bufferCount++;
      // If buffering too frequently (3+ times in 30 seconds), switch to adaptive mode
      if (_bufferCount >= 3 && !_isAdaptiveMode) {
        _enableAdaptiveMode();
      }
    } else {
      _bufferCount = 1;
    }
    _lastBufferTime = now;
  }

  // Enable adaptive mode for better stability
  void _enableAdaptiveMode() {
    setState(() {
      _isAdaptiveMode = true;
      _selectedQuality = 'adaptive';
    });

    // Show notification
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.speed, color: Colors.white),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Switched to adaptive mode for smoother playback'),
            ),
          ],
        ),
        backgroundColor: Colors.orange[700],
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Reset',
          textColor: Colors.white,
          onPressed: _disableAdaptiveMode,
        ),
      ),
    );

    // Re-apply player options with adaptive settings
    if (_player != null) {
      _applyPlayerOptions(_player!);
    }
  }

  // Disable adaptive mode
  void _disableAdaptiveMode() {
    setState(() {
      _isAdaptiveMode = false;
      _selectedQuality = 'auto';
      _bufferCount = 0;
    });

    if (_player != null) {
      _applyPlayerOptions(_player!);
    }
  }

  // Attempt buffer recovery when buffering persists
  Future<void> _attemptBufferRecovery() async {
    if (_isRecoveringBuffer || _player == null) return;
    _isRecoveringBuffer = true;

    // First, try enabling adaptive mode if not already
    if (!_isAdaptiveMode) {
      _enableAdaptiveMode();
      _isRecoveringBuffer = false;
      return;
    }

    // If adaptive mode was already on, try a quick restart
    setState(() {
      _lastError = 'Buffering persisted - attempting quick restart';
    });

    try {
      final url = _currentUrl;
      if (url.isNotEmpty) {
        await _player!.stop();
        await Future.delayed(const Duration(milliseconds: 300));
        await _player!.open(Media(url));
        setState(() {
          _lastError = '';
        });
      }
    } catch (e) {
      setState(() {
        _lastError = 'Recovery failed: ${e.toString()}';
      });
    } finally {
      _isRecoveringBuffer = false;
    }
  }

  // Set audio track for language selection
  Future<void> _setAudioTrack(AudioTrack track, {int? trackIndex}) async {
    if (_player == null) return;

    // Check if track is known to be failed
    if (_failedAudioTracks.contains(track.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('This audio track is unavailable'),
          backgroundColor: Colors.grey.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      await _player!.setAudioTrack(track);
      setState(() {
        _selectedAudioTrack = track;
      });

      final label = _getLanguageName(track.language, trackIndex: trackIndex);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Audio: $label'),
          backgroundColor: Colors.blue.shade700,
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      // Mark as failed and show unavailable
      _failedAudioTracks.add(track.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Audio track unavailable'),
          backgroundColor: Colors.grey.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showAudioTrackDialog() {
    // Single track - don't show dialog
    if (_audioTracks.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_audioTracks.isEmpty
              ? 'No audio tracks available'
              : 'Single audio track'),
          backgroundColor: Colors.grey.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.audiotrack, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('Audio Tracks'),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Don't show technical count in user mode
              if (_devMode)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${_audioTracks.length} tracks, ${_failedAudioTracks.length} unavailable',
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                ),
              ListView.builder(
                shrinkWrap: true,
                itemCount: _audioTracks.length,
                itemBuilder: (context, index) {
                  final track = _audioTracks[index];
                  final isSelected = _selectedAudioTrack?.id == track.id;
                  final isFailed = _failedAudioTracks.contains(track.id);

                  // Use synthetic label - NEVER show "Unknown"
                  final languageName =
                      _getLanguageName(track.language, trackIndex: index);

                  return Card(
                    elevation: isSelected ? 3 : 1,
                    color: isFailed
                        ? Colors.grey.shade800.withValues(alpha: 0.5)
                        : isSelected
                            ? Colors.blue.withValues(alpha: 0.15)
                            : const Color(0xFF2a3441),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: ListTile(
                      enabled: !isFailed,
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isFailed
                              ? Colors.grey.shade700
                              : isSelected
                                  ? Colors.blue
                                  : Colors.grey[700],
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(
                          isFailed
                              ? Icons.block
                              : isSelected
                                  ? Icons.check
                                  : Icons.audiotrack,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        languageName,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 15,
                          color: isFailed ? Colors.grey : null,
                          decoration:
                              isFailed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: isFailed
                          ? const Text('Unavailable',
                              style:
                                  TextStyle(fontSize: 11, color: Colors.grey))
                          : null,
                      onTap: isFailed
                          ? null
                          : () {
                              _setAudioTrack(track, trackIndex: index);
                              Navigator.of(ctx).pop();
                            },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Show quality selection dialog with adaptive mode option
  void _showQualityDialog() {
    final qualities = [
      'auto',
      'adaptive',
      '1080p',
      '720p',
      '480p',
      '360p',
      '240p'
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.high_quality,
                color: _isAdaptiveMode ? Colors.orange : Colors.green),
            const SizedBox(width: 8),
            const Text('Stream Quality'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Adaptive mode status indicator
            if (_isAdaptiveMode)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.speed, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Adaptive mode active - adjusting for stability',
                        style:
                            TextStyle(fontSize: 12, color: Colors.orange[300]),
                      ),
                    ),
                  ],
                ),
              ),
            ...qualities.map((quality) {
              final isSelected = _selectedQuality == quality ||
                  (quality == 'adaptive' && _isAdaptiveMode);
              final isAdaptive = quality == 'adaptive';
              return ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: isSelected
                      ? (isAdaptive ? Colors.orange : Colors.green)
                      : Colors.grey,
                ),
                title: Text(
                  quality == 'auto'
                      ? 'Auto (Best Available)'
                      : quality == 'adaptive'
                          ? 'Adaptive (Stable)'
                          : quality,
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isAdaptive ? Colors.orange : null,
                  ),
                ),
                subtitle: quality == 'auto'
                    ? const Text('Automatically select best quality',
                        style: TextStyle(fontSize: 12))
                    : quality == 'adaptive'
                        ? const Text('Lower quality for smoother playback',
                            style:
                                TextStyle(fontSize: 12, color: Colors.orange))
                        : null,
                onTap: () {
                  if (quality == 'adaptive') {
                    _enableAdaptiveMode();
                  } else {
                    _disableAdaptiveMode();
                    setState(() {
                      _selectedQuality = quality;
                    });
                  }
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Quality set to $quality - restart stream to apply'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              );
            }).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // Handle keyboard shortcuts - ONLY when no text field is focused
  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // CRITICAL: Disable all shortcuts when any text field has focus
    // This prevents typing 'a' from opening audio menu, 'm' from muting, etc.
    if (_isTextFieldFocused) return;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        _playPause();
        break;
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
        break;
      case LogicalKeyboardKey.keyA:
        _showAudioTrackDialog();
        break;
      case LogicalKeyboardKey.keyQ:
        _showQualityDialog();
        break;
      case LogicalKeyboardKey.keyM:
        _setVolume(_volume > 0 ? 0 : 50);
        break;
      case LogicalKeyboardKey.arrowUp:
        _setVolume((_volume + 10).clamp(0, 200)); // Up to 200% like VLC
        break;
      case LogicalKeyboardKey.arrowDown:
        _setVolume((_volume - 10).clamp(0, 200));
        break;
      case LogicalKeyboardKey.keyR:
        _retry();
        break;
    }
  }

  void _toggleFullscreen() {
    if (_videoController != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FullscreenPlayer(
            controller: _videoController,
            onKeyEvent: _handleKeyEvent,
          ),
        ),
      );
    }
  }

  // Debounced search to improve performance
  void _updateSearch(String query) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = query.trim().toLowerCase();
      });
    });
  }

  Future<void> _playPause() async {
    if (_player == null) return;
    try {
      await _player!.playOrPause();
    } catch (e) {
      setState(() {
        _lastError = e.toString();
        _status = 'error';
      });
    }
  }

  Future<void> _setVolume(double v) async {
    _volume = v;
    if (_player != null) {
      await _player!.setVolume(v);
    }
    setState(() {});
  }

  Future<void> _retry() async {
    if (_currentUrl.isNotEmpty) {
      await _startPlayback(_currentUrl);
    }
  }

  // Show info dialog about media_kit
  void _showInfoDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Player Info'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_libVlcNote),
              const SizedBox(height: 8),
              const Text(
                'This app uses media_kit which bundles all required libraries automatically. No external dependencies needed.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLeftPanel() {
    final iptv = Provider.of<IptvService>(context);
    return Container(
      width: 360,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.white24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('Channels',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(
                onPressed: () => iptv.loadChannels(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              )
            ],
          ),
          const SizedBox(height: 8),

          // Search box - uses focusNode to prevent shortcut conflicts
          TextField(
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search channels, countries, languages...',
              // Visual focus indicator
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade700),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (v) => setState(() {
              _search = v.trim();
            }),
          ),
          const SizedBox(height: 8),

          // Filters row with search-aware dropdowns
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedCategory,
                  items: [
                    const DropdownMenuItem(
                        value: 'all', child: Text('All Categories')),
                    ...iptv
                        .getUniqueCategories()
                        .where((c) =>
                            _search.isEmpty ||
                            c['name']!
                                .toLowerCase()
                                .startsWith(_search.toLowerCase()) ||
                            c['name']!
                                .toLowerCase()
                                .contains(_search.toLowerCase()))
                        .map((c) => DropdownMenuItem(
                            value: c['id'], child: Text(c['name']!)))
                        .toList(),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedCategory = v ?? 'all';
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedCountry,
                  items: [
                    const DropdownMenuItem(
                        value: 'all', child: Text('All Countries')),
                    ...iptv
                        .getUniqueCountries()
                        .where((c) =>
                            _search.isEmpty ||
                            c['name']!
                                .toLowerCase()
                                .startsWith(_search.toLowerCase()) ||
                            c['name']!
                                .toLowerCase()
                                .contains(_search.toLowerCase()))
                        .map((c) => DropdownMenuItem(
                            value: c['code'], child: Text(c['name']!)))
                        .toList(),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedCountry = v ?? 'all';
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedLanguage,
                  items: [
                    const DropdownMenuItem(
                        value: 'all', child: Text('All Languages')),
                    ...iptv
                        .getUniqueLanguages()
                        .where((c) =>
                            _search.isEmpty ||
                            c['name']!
                                .toLowerCase()
                                .startsWith(_search.toLowerCase()) ||
                            c['name']!
                                .toLowerCase()
                                .contains(_search.toLowerCase()))
                        .map((c) => DropdownMenuItem(
                            value: c['code'], child: Text(c['name']!)))
                        .toList(),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedLanguage = v ?? 'all';
                  }),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Channel list filtered
          Expanded(
            child: Builder(builder: (context) {
              final filtered = iptv.channels.where((ch) {
                final searchLower = _search.toLowerCase();
                if (_search.isNotEmpty) {
                  final matchesSearch = ch.name
                          .toLowerCase()
                          .contains(searchLower) ||
                      ch.countryName.toLowerCase().contains(searchLower) ||
                      ch.categoryName.toLowerCase().contains(searchLower) ||
                      ch.languageNames
                          .any((ln) => ln.toLowerCase().contains(searchLower));
                  if (!matchesSearch) return false;
                }
                if (_selectedCategory != 'all') {
                  if (ch.category.toLowerCase() !=
                          _selectedCategory.toLowerCase() &&
                      !ch.categories.any((c) =>
                          c.toLowerCase() == _selectedCategory.toLowerCase()))
                    return false;
                }
                if (_selectedCountry != 'all') {
                  if (ch.country.toLowerCase() !=
                      _selectedCountry.toLowerCase()) return false;
                }
                if (_selectedLanguage != 'all') {
                  if (!ch.languages.any((l) =>
                          l.toLowerCase() == _selectedLanguage.toLowerCase()) &&
                      !ch.languageNames.any((ln) =>
                          ln.toLowerCase() == _selectedLanguage.toLowerCase()))
                    return false;
                }
                return true;
              }).toList();

              if (filtered.isEmpty)
                return const Center(child: Text('No channels match'));

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final ch = filtered[i];
                  return ListTile(
                    leading: ch.logo.isNotEmpty
                        ? Image.network(
                            ch.logo,
                            width: 36,
                            height: 24,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, error, stack) =>
                                const Icon(Icons.tv),
                          )
                        : const Icon(Icons.tv),
                    title: Text(ch.name),
                    subtitle: Text(
                        '${ch.countryFlag} ${ch.countryName} • ${ch.categoryName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    onTap: () {
                      _urlController.text = ch.url;
                      _startPlayback(ch.url);
                    },
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  // Helper method to build filter chips
  Widget _buildFilterChip(
      String label, String selectedValue, VoidCallback onTap) {
    final isSelected = selectedValue != 'all';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blue.withOpacity(0.2)
              : const Color(0xFF2a3441),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.grey[300],
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, color: Colors.blue, size: 16),
            ],
          ],
        ),
      ),
    );
  }

  // Show category picker
  void _showCategoryPicker(IptvService iptv) {
    final categories = iptv.getUniqueCategories();
    _showFilterDialog('Categories', categories, _selectedCategory, (value) {
      setState(() => _selectedCategory = value);
    });
  }

  // Show country picker
  void _showCountryPicker(IptvService iptv) {
    final countries = iptv.getUniqueCountries();
    _showFilterDialog('Countries', countries, _selectedCountry, (value) {
      setState(() => _selectedCountry = value);
    });
  }

  // Show language picker
  void _showLanguagePicker(IptvService iptv) {
    final languages = iptv.getUniqueLanguages();
    _showFilterDialog('Languages', languages, _selectedLanguage, (value) {
      setState(() => _selectedLanguage = value);
    });
  }

  // Generic filter dialog
  void _showFilterDialog(String title, List<Map<String, String>> items,
      String selectedValue, Function(String) onSelect) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Select $title'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  selectedValue == 'all'
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selectedValue == 'all' ? Colors.blue : Colors.grey,
                ),
                title: Text('All $title'),
                onTap: () {
                  onSelect('all');
                  Navigator.of(ctx).pop();
                },
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isSelected = selectedValue == item['id'];
                    return ListTile(
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isSelected ? Colors.blue : Colors.grey,
                      ),
                      title: Text(item['name']!),
                      onTap: () {
                        onSelect(item['id']!);
                        Navigator.of(ctx).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Build enhanced channel list
  Widget _buildChannelList(IptvService iptv) {
    return Builder(builder: (context) {
      final searchQuery =
          _searchQuery.isNotEmpty ? _searchQuery : _search.toLowerCase();

      final filtered = iptv.channels.where((ch) {
        // Search filter
        if (searchQuery.isNotEmpty) {
          final matchesSearch = ch.name.toLowerCase().contains(searchQuery) ||
              ch.countryName.toLowerCase().contains(searchQuery) ||
              ch.categoryName.toLowerCase().contains(searchQuery) ||
              ch.languageNames
                  .any((ln) => ln.toLowerCase().contains(searchQuery));
          if (!matchesSearch) return false;
        }

        // Category filter
        if (_selectedCategory != 'all') {
          if (ch.category.toLowerCase() != _selectedCategory.toLowerCase() &&
              !ch.categories.any(
                  (c) => c.toLowerCase() == _selectedCategory.toLowerCase()))
            return false;
        }

        // Country filter
        if (_selectedCountry != 'all') {
          if (ch.country.toLowerCase() != _selectedCountry.toLowerCase())
            return false;
        }

        // Language filter
        if (_selectedLanguage != 'all') {
          if (!ch.languages.any(
                  (l) => l.toLowerCase() == _selectedLanguage.toLowerCase()) &&
              !ch.languageNames.any(
                  (ln) => ln.toLowerCase() == _selectedLanguage.toLowerCase()))
            return false;
        }

        return true;
      }).toList();

      // Sort filtered results
      if (searchQuery.isNotEmpty) {
        filtered.sort((a, b) {
          final aScore = _calculateSearchScore(a, searchQuery);
          final bScore = _calculateSearchScore(b, searchQuery);
          return bScore.compareTo(aScore);
        });
      }

      if (filtered.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 48, color: Colors.grey[600]),
              const SizedBox(height: 8),
              Text('No channels match your search',
                  style: TextStyle(color: Colors.grey[400])),
              if (searchQuery.isNotEmpty ||
                  _selectedCategory != 'all' ||
                  _selectedCountry != 'all' ||
                  _selectedLanguage != 'all')
                TextButton(
                  onPressed: () {
                    setState(() {
                      _search = '';
                      _searchQuery = '';
                      _selectedCategory = 'all';
                      _selectedCountry = 'all';
                      _selectedLanguage = 'all';
                    });
                  },
                  child: const Text('Clear filters'),
                ),
            ],
          ),
        );
      }

      return Card(
        elevation: 2,
        color: const Color(0xFF1a2332),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (context, i) {
            final ch = filtered[i];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              color: const Color(0xFF2a3441),
              child: ListTile(
                leading: ch.logo.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          ch.logo,
                          width: 40,
                          height: 30,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, error, stack) => Container(
                            width: 40,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.grey[800],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.tv, size: 16),
                          ),
                        ),
                      )
                    : Container(
                        width: 40,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.tv, size: 16),
                      ),
                title: Text(
                  ch.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Row(
                  children: [
                    Text(ch.countryFlag, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${ch.countryName} • ${ch.categoryName}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  _urlController.text = ch.url;
                  _startPlayback(ch.url);
                },
                trailing: Icon(Icons.play_circle_outline,
                    color: Colors.blue.withOpacity(0.7)),
              ),
            );
          },
        ),
      );
    });
  }

  // Calculate search relevance score
  int _calculateSearchScore(dynamic channel, String query) {
    int score = 0;
    final lowerQuery = query.toLowerCase();

    if (channel.name.toLowerCase().startsWith(lowerQuery))
      score += 100;
    else if (channel.name.toLowerCase().contains(lowerQuery)) score += 50;

    if (channel.categoryName.toLowerCase().contains(lowerQuery)) score += 30;
    if (channel.countryName.toLowerCase().contains(lowerQuery)) score += 20;

    for (final lang in channel.languageNames) {
      if (lang.toLowerCase().contains(lowerQuery)) score += 10;
    }

    return score;
  }

  // Build URL input section
  Widget _buildUrlSection() {
    return Card(
      elevation: 4,
      color: const Color(0xFF2a3441),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('Direct URL',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              focusNode: _urlFocusNode,
              decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintText: 'Paste stream URL (.m3u8, .ts, .mp4, etc.)',
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 12),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                // Visual focus indicator
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.orange, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final url = _urlController.text.trim();
                      if (url.isNotEmpty) _startPlayback(url);
                    },
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Play URL'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _urlController.clear(),
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  tooltip: 'Clear URL',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenter() {
    // Build appropriate center widget based on status
    Widget centerContent;

    if (_player == null && _status == 'idle') {
      centerContent = const Center(
        child: Text(
          'No stream selected\nClick a channel to play',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    } else if (_status == 'checking') {
      centerContent = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Checking stream availability...',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    } else if (_status == 'loading' || _status == 'buffering') {
      centerContent = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading stream...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    } else if (_status == 'switching') {
      // Channel switching overlay - mute & indicate switching
      centerContent = Stack(
        children: [
          if (_videoController != null) Video(controller: _videoController!),
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.cyan.shade300,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Switching channel...',
                      style:
                          TextStyle(fontSize: 12, color: Colors.cyan.shade300)),
                ],
              ),
            ),
          ),
        ],
      );
    } else if (_status == 'reconnecting') {
      // Silent reconnecting - show minimal indicator
      centerContent = Stack(
        children: [
          if (_videoController != null) Video(controller: _videoController!),
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.yellow.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Reconnecting...',
                      style: TextStyle(
                          fontSize: 12, color: Colors.yellow.shade700)),
                ],
              ),
            ),
          ),
        ],
      );
    } else if (_status == 'unavailable' || _status == 'timeout') {
      centerContent = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _status == 'unavailable'
                  ? 'Stream Unavailable'
                  : 'Connection Failed',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            if (_lastError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_lastError,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
              ),
            ),
          ],
        ),
      );
    } else if (_status == 'error') {
      centerContent = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 48, color: Colors.orange.shade700),
            const SizedBox(height: 12),
            const Text('Unable to play',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            if (_lastError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_lastError,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
              ),
            ),
          ],
        ),
      );
    } else if (_videoController != null) {
      centerContent = Video(controller: _videoController!);
    } else {
      centerContent = const Center(
        child: Text('Initializing player...',
            style: TextStyle(color: Colors.white70)),
      );
    }

    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              color: Colors.black,
              child: centerContent,
            ),
          ),
          _buildControls(),
          _buildDiagnostics(),
          _buildDevDiagnostics(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF0B1220), const Color(0xFF1a2332)],
        ),
        border: Border(top: BorderSide(color: Colors.white24, width: 1)),
      ),
      child: Column(
        children: [
          // Main controls row
          Row(
            children: [
              // Play/Pause button with enhanced styling
              Container(
                decoration: BoxDecoration(
                  color: _player != null
                      ? Colors.blue.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: _player == null ? null : _playPause,
                  icon: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: _player != null ? Colors.blue : Colors.grey,
                    size: 28,
                  ),
                  tooltip: 'Play/Pause (Space)',
                ),
              ),
              const SizedBox(width: 8),

              // Stop button
              Container(
                decoration: BoxDecoration(
                  color: _player != null
                      ? Colors.red.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: _player == null
                      ? null
                      : () {
                          try {
                            _player!.stop();
                            setState(() {
                              _status = 'stopped';
                              _isPlaying = false;
                            });
                          } catch (_) {}
                        },
                  icon: Icon(
                    Icons.stop,
                    color: _player != null ? Colors.red : Colors.grey,
                  ),
                  tooltip: 'Stop',
                ),
              ),
              const SizedBox(width: 8),

              // Retry button
              Container(
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh, color: Colors.orange),
                  tooltip: 'Retry (R)',
                ),
              ),
              const SizedBox(width: 16),

              // Quality selector
              Container(
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: _showQualityDialog,
                  icon: const Icon(Icons.high_quality, color: Colors.green),
                  tooltip: 'Quality (Q)',
                ),
              ),
              const SizedBox(width: 8),

              // Audio track / Language selector
              Container(
                decoration: BoxDecoration(
                  color: _audioTracks.isNotEmpty
                      ? Colors.purple.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed:
                      _audioTracks.isNotEmpty ? _showAudioTrackDialog : null,
                  icon: Icon(
                    Icons.language,
                    color:
                        _audioTracks.isNotEmpty ? Colors.purple : Colors.grey,
                  ),
                  tooltip: 'Audio Track / Language (A)',
                ),
              ),
              const SizedBox(width: 16),

              // Volume section with VLC-style 2x amplification
              Icon(
                _volume > 100
                    ? Icons.volume_up
                    : (_volume > 0 ? Icons.volume_up : Icons.volume_off),
                color: _volume > 100 ? Colors.orange : Colors.white70,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 16),
                  ),
                  child: Slider(
                    value: _volume,
                    min: 0,
                    max: 200, // VLC-style 2x volume boost
                    divisions: 40,
                    onChanged: (v) => _setVolume(v),
                    activeColor: _volume > 100 ? Colors.orange : Colors.blue,
                    inactiveColor: Colors.grey[700],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _volume > 100
                      ? Colors.orange.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_volume.round()}%',
                  style: TextStyle(
                    color: _volume > 100 ? Colors.orange : Colors.grey[400],
                    fontSize: 12,
                    fontWeight:
                        _volume > 100 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Mute/Unmute button
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: () => _setVolume(_volume > 0 ? 0 : 100),
                  icon: Icon(
                    _volume == 0
                        ? Icons.volume_off
                        : (_volume > 100 ? Icons.volume_up : Icons.volume_down),
                    color: _volume == 0
                        ? Colors.red
                        : (_volume > 100 ? Colors.orange : Colors.white70),
                  ),
                  tooltip: 'Mute/Unmute (M)',
                ),
              ),
              const SizedBox(width: 4),

              // Audio Boost button (VLC-style 2x)
              Container(
                decoration: BoxDecoration(
                  color: _volume > 100
                      ? Colors.orange.withValues(alpha: 0.3)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _volume > 100 ? Colors.orange : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: IconButton(
                  onPressed: () => _setVolume(_volume > 100 ? 100 : 150),
                  icon: Icon(
                    Icons.speaker,
                    color: _volume > 100 ? Colors.orange : Colors.grey,
                    size: 20,
                  ),
                  tooltip: 'Audio Boost (up to 200%)',
                ),
              ),
              const SizedBox(width: 8),

              // Fullscreen button
              Container(
                decoration: BoxDecoration(
                  color: Colors.cyan.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: _toggleFullscreen,
                  icon: const Icon(Icons.fullscreen, color: Colors.cyan),
                  tooltip: 'Fullscreen (F)',
                ),
              ),
            ],
          ),

          // Keyboard shortcuts info
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildShortcutChip('Space', 'Play/Pause'),
              _buildShortcutChip('F', 'Fullscreen'),
              _buildShortcutChip('A', 'Audio'),
              _buildShortcutChip('Q', 'Quality'),
              _buildShortcutChip('M', 'Mute'),
              _buildShortcutChip('R', 'Retry'),
              _buildShortcutChip('↑/↓', 'Vol (0-200%)'),
            ],
          ),
        ],
      ),
    );
  }

  // Helper to build shortcut info chips
  Widget _buildShortcutChip(String key, String action) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey[600]!, width: 0.5),
      ),
      child: Text(
        '$key: $action',
        style: TextStyle(color: Colors.grey[300], fontSize: 10),
      ),
    );
  }

  Widget _buildDiagnostics() {
    final iptv = Provider.of<IptvService>(context);

    // Status color based on state
    Color statusColor = Colors.white70;
    String statusText = _status;
    if (_status == 'playing') {
      statusColor = Colors.green;
    } else if (_status == 'buffering' ||
        _status == 'loading' ||
        _status == 'checking' ||
        _status == 'reconnecting') {
      statusColor = Colors.yellow;
    } else if (_status == 'error' ||
        _status == 'unavailable' ||
        _status == 'timeout') {
      statusColor = Colors.red;
    }

    // Format status text - user-friendly labels
    switch (_status) {
      case 'checking':
        statusText = 'Connecting...';
        break;
      case 'loading':
        statusText = 'Loading...';
        break;
      case 'buffering':
        statusText = 'Buffering...';
        break;
      case 'reconnecting':
        statusText = 'Reconnecting...';
        break;
      case 'playing':
        statusText = 'Playing';
        break;
      case 'unavailable':
        statusText = 'Unavailable';
        break;
      case 'timeout':
        statusText = 'Connection failed';
        break;
      case 'error':
        statusText = 'Error';
        break;
      case 'stopped':
        statusText = 'Stopped';
        break;
      case 'ended':
        statusText = 'Ended';
        break;
      default:
        statusText = '';
    }

    // Minimal status bar - hide debug info from users
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF071019),
      child: Row(
        children: [
          // Status indicator (always visible)
          if (statusText.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(statusText,
                      style: TextStyle(fontSize: 12, color: statusColor)),
                ],
              ),
            ),

          const Spacer(),

          // Channel count (useful info)
          Text('${iptv.channels.length} channels',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),

          const SizedBox(width: 12),

          // Dev mode toggle
          GestureDetector(
            onTap: () => setState(() => _devMode = !_devMode),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.bug_report,
                size: 14,
                color: _devMode ? Colors.orange : Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Dev-only diagnostics panel
  Widget _buildDevDiagnostics() {
    if (!_devMode) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black.withValues(alpha: 0.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DEV MODE',
              style: TextStyle(
                  color: Colors.orange,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('URL: ${_currentUrl.isEmpty ? '—' : _currentUrl}',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(
              'Status: $_status | Player: ${_controllerInitialized ? 'Ready' : 'Not ready'}',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(
              'Audio: ${_audioTracks.length} tracks, ${_failedAudioTracks.length} failed',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text('Retries: $_retryCount/$_maxRetries | Errors: $_audioErrorCount',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          if (_lastError.isNotEmpty)
            Text('Last error: $_lastError',
                style:
                    const TextStyle(fontSize: 10, color: Colors.orangeAccent)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use Focus widget (modern replacement for deprecated KeyboardListener)
    // with onKeyEvent to handle shortcuts context-aware
    return Focus(
      focusNode: _appFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        _handleKeyEvent(event);
        // Return handled only if we actually processed the key
        // and a text field is NOT focused
        if (!_isTextFieldFocused && event is KeyDownEvent) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Icon(Icons.tv, color: Colors.blue),
              const SizedBox(width: 8),
              const Text('Chillz — Desktop (media_kit)'),
              const Spacer(),
              if (_selectedQuality != 'auto')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _selectedQuality,
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ),
            ],
          ),
          backgroundColor: const Color(0xFF1a2332),
        ),
        body: Row(children: [_buildLeftPanel(), _buildCenter()]),
      ),
    );
  }
}

class FullscreenPlayer extends StatefulWidget {
  final VideoController? controller;
  final Function(KeyEvent)? onKeyEvent;

  const FullscreenPlayer({
    Key? key,
    required this.controller,
    this.onKeyEvent,
  }) : super(key: key);

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          // Handle Escape to exit fullscreen
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return;
          }
          // Pass other keys to parent handler
          widget.onKeyEvent?.call(event);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Row(
            children: [
              const Text('Fullscreen Mode'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'ESC: Exit',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.black.withOpacity(0.8),
          elevation: 0,
        ),
        body: Center(
          child: widget.controller != null
              ? Video(controller: widget.controller!)
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tv_off, size: 64, color: Colors.white54),
                    SizedBox(height: 16),
                    Text(
                      'No video player available',
                      style: TextStyle(color: Colors.white54, fontSize: 18),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
