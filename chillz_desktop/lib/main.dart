// Chillz Flutter - Direct libVLC Integration
// NO media_kit, NO FFmpeg wrapper - Pure VLC behavior
// Flutter handles UI ONLY, VLC handles ALL media playback

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;

import 'models/iptv_models.dart';
import 'services/iptv_service.dart';
import 'services/vlc_player_service.dart';

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

  // NO MediaKit.ensureInitialized() - we use pure libVLC!
  debugPrint('[Chillz] Starting with direct libVLC integration');

  runApp(const ChillzApp());
}

class ChillzApp extends StatelessWidget {
  const ChillzApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => IptvService()..loadChannels()),
        ChangeNotifierProvider(create: (_) => VlcPlayerController()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Chillz — TV',
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

class _ChillzHomeState extends State<ChillzHome> with WidgetsBindingObserver {
  late IptvService _iptvService;
  late VlcPlayerController _vlc;
  bool _vlcServiceReady = false; // Guard against build before _vlc is assigned

  String _currentUrl = '';
  String _status = 'idle';
  String _lastError = '';
  double _volume = 100.0;

  // Audio tracks
  List<VlcAudioTrack> _audioTracks = [];
  int _selectedAudioTrack = -1;
  Set<int> _failedAudioTracks = {};

  // Dev mode
  bool _devMode =
      false; // DEBUG: enable automated attach/play for validation in debug builds

  // Search & Filters
  String _search = '';
  String _selectedCategory = 'all';
  String _selectedCountry = 'all';
  String _selectedLanguage = 'all';
  Timer? _searchTimer;
  String _searchQuery = '';

  // Filter search (typeahead)
  String _categoryFilter = '';
  String _countryFilter = '';
  String _languageFilter = '';

  // Cached filtered channels to prevent UI blocking
  List<Channel> _filteredChannels = [];
  bool _filterDirty = true;

  // Focus management - Track ALL text fields to prevent shortcuts during typing
  final FocusNode _appFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _urlFocusNode = FocusNode();
  final FocusNode _categoryFilterFocusNode = FocusNode();
  final FocusNode _countryFilterFocusNode = FocusNode();
  final FocusNode _languageFilterFocusNode = FocusNode();
  bool _isTextFieldFocused = false;

  final _urlController = TextEditingController();

  // Pagination
  static const int _pageSize = 50;
  int _currentPage = 0;
  bool _isLoadingMore = false;

  // GlobalKey for video container - CRITICAL for accurate layout
  final GlobalKey _videoContainerKey = GlobalKey();

  // Fullscreen state
  bool _isFullscreen = false;

  // FIX: Throttle HWND updates - only send when bounds actually change
  Rect? _lastBounds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _iptvService = Provider.of<IptvService>(context, listen: false);
      _vlc = Provider.of<VlcPlayerController>(context, listen: false);

      // Mark service as ready - prevents LateInitializationError on first build
      setState(() {
        _vlcServiceReady = true;
      });

      if (!_iptvService.loading && _iptvService.channels.isEmpty) {
        _iptvService.loadChannels();
      }

      // Initialize VLC - this now auto-creates the child HWND for video rendering
      final pluginsPath = _getPluginsPath();
      debugPrint('[Chillz] Initializing VLC with plugins: $pluginsPath');

      final initOk = await _vlc.initialize(pluginsPath: pluginsPath);
      if (initOk) {
        setState(() {
          _status = 'ready';
        });
        debugPrint(
            '[Chillz] VLC initialized successfully (child HWND created)');

        // FIX 1: Double post-frame callback for reliable layout timing
        // First callback waits for layout, second ensures it's stable
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateVideoBounds();
          });
        });

        // DEV: auto-attach and play a test stream for verification in debug mode
        if (_devMode) {
          final testUrl =
              'https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8';
          Future.microtask(() async {
            final attached = await _vlc.attachVideo(width: 0, height: 0);
            debugPrint('[Chillz] Auto attachVideo result: $attached');
            if (attached) {
              // FIX 1: Double post-frame callback BEFORE playing
              WidgetsBinding.instance.addPostFrameCallback((_) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  await _updateVideoBounds();
                });
              });
              final played = await _vlc.play(testUrl);
              debugPrint('[Chillz] Auto play result: $played');
              // FIX 5: One-time delayed resize 300ms after play
              await Future.delayed(const Duration(milliseconds: 300));
              await _updateVideoBounds();
            }
          });
        }
      } else {
        setState(() {
          _status = 'error';
          _lastError =
              'Failed to initialize VLC. Check libvlc.dll and plugins folder.';
        });
        debugPrint('[Chillz] VLC initialization failed');
      }

      // Listen to VLC state changes
      _vlc.addListener(_onVlcStateChanged);

      // Set up focus listeners for ALL text fields
      _searchFocusNode.addListener(_onTextFieldFocusChange);
      _urlFocusNode.addListener(_onTextFieldFocusChange);
      _categoryFilterFocusNode.addListener(_onTextFieldFocusChange);
      _countryFilterFocusNode.addListener(_onTextFieldFocusChange);
      _languageFilterFocusNode.addListener(_onTextFieldFocusChange);
    });
  }

  /// CRITICAL: Update video HWND bounds from Flutter layout
  /// Uses GlobalKey, RenderBox, and devicePixelRatio for pixel-perfect positioning
  Future<void> _updateVideoBounds() async {
    if (!_vlc.initialized) return;

    final RenderObject? renderObject =
        _videoContainerKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) {
      debugPrint('[Chillz] _updateVideoBounds: RenderBox not found');
      return;
    }

    final RenderBox box = renderObject;
    if (!box.hasSize) {
      debugPrint('[Chillz] _updateVideoBounds: RenderBox has no size yet');
      return;
    }

    // Get global position of the video container
    final Offset globalPosition = box.localToGlobal(Offset.zero);
    final Size size = box.size;

    // Get devicePixelRatio for DPI scaling
    final double dpr = MediaQuery.of(context).devicePixelRatio;

    // Compute physical pixel values
    final int x = (globalPosition.dx * dpr).round();
    final int y = (globalPosition.dy * dpr).round();
    final int width = (size.width * dpr).round();
    final int height = (size.height * dpr).round();

    // FIX 2: Throttle - only update if bounds actually changed
    final newBounds = Rect.fromLTWH(
        x.toDouble(), y.toDouble(), width.toDouble(), height.toDouble());
    if (_lastBounds != null && _lastBounds == newBounds) {
      debugPrint('[Chillz] _updateVideoBounds: skipped (unchanged)');
      return;
    }
    _lastBounds = newBounds;

    debugPrint(
        '[Chillz] _updateVideoBounds: x=$x, y=$y, w=$width, h=$height (dpr=$dpr)');

    await _vlc.setVideoBounds(x, y, width, height);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // FIX 1: Double post-frame callback for stable resize handling
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateVideoBounds();
      });
    });
  }

  String _getPluginsPath() {
    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;
    return '$exeDir\\plugins';
  }

  void _onVlcStateChanged() {
    if (!mounted) return;

    setState(() {
      switch (_vlc.state) {
        case VlcState.opening:
          _status = 'loading';
          break;
        case VlcState.buffering:
          _status = 'buffering';
          break;
        case VlcState.playing:
          _status = 'playing';
          break;
        case VlcState.paused:
          _status = 'paused';
          break;
        case VlcState.stopped:
          _status = 'stopped';
          break;
        case VlcState.ended:
          _status = 'ended';
          break;
        case VlcState.error:
          _status = 'error';
          _lastError = _vlc.lastError ?? 'Unknown error';
          break;
        case VlcState.idle:
          if (_status != 'switching') {
            _status = 'idle';
          }
          break;
      }

      // Update audio tracks
      _audioTracks = _vlc.audioTracks;
      _selectedAudioTrack = _vlc.currentAudioTrack;
      _volume = _vlc.volume.toDouble();
    });
  }

  void _onTextFieldFocusChange() {
    setState(() {
      _isTextFieldFocused = _searchFocusNode.hasFocus ||
          _urlFocusNode.hasFocus ||
          _categoryFilterFocusNode.hasFocus ||
          _countryFilterFocusNode.hasFocus ||
          _languageFilterFocusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vlc.removeListener(_onVlcStateChanged);
    _vlc.dispose();
    _urlController.dispose();
    _searchTimer?.cancel();
    _searchFocusNode.removeListener(_onTextFieldFocusChange);
    _urlFocusNode.removeListener(_onTextFieldFocusChange);
    _categoryFilterFocusNode.removeListener(_onTextFieldFocusChange);
    _countryFilterFocusNode.removeListener(_onTextFieldFocusChange);
    _languageFilterFocusNode.removeListener(_onTextFieldFocusChange);
    _appFocusNode.dispose();
    _searchFocusNode.dispose();
    _urlFocusNode.dispose();
    _categoryFilterFocusNode.dispose();
    _countryFilterFocusNode.dispose();
    _languageFilterFocusNode.dispose();
    super.dispose();
  }

  /// Load more channels with SchedulerBinding for smooth UI
  void _loadMoreChannels() {
    if (_isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    // Use SchedulerBinding.addPostFrameCallback for smooth loading
    SchedulerBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _currentPage++;
        _isLoadingMore = false;
      });
    });
  }

  /// Toggle fullscreen mode - Flutter controls fullscreen, VLC only renders
  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    // FIX 1: Double post-frame callback for stable fullscreen transition
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateVideoBounds();
      });
    });
    debugPrint('[Chillz] Fullscreen: $_isFullscreen');
  }

  /// Start playback - VLC handles EVERYTHING
  Future<void> _startPlayback(String url) async {
    setState(() {
      _status = 'switching';
      _currentUrl = url;
      _lastError = '';
      _audioTracks = [];
      _selectedAudioTrack = -1;
    });

    debugPrint('[Chillz] Starting playback: $url');

    // VLC handles everything - stop, release, create, play
    // This is the CRITICAL part - VLC will:
    // 1. Stop current playback (kills audio immediately)
    // 2. Release old media
    // 3. Create new media
    // 4. Start playback
    // NO ghost audio because libvlc_media_player_stop() is synchronous

    // Proactive URL Check
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 403) {
        setState(() {
          _status = 'error';
          _lastError =
              'Access Denied (403). Try finding a working proxy, or use a VPN.';
        });
        return;
      } else if (response.statusCode == 404) {
        setState(() {
          _status = 'error';
          _lastError = 'Stream Not Found (404). This link is no longer valid.';
        });
        return;
      }
    } catch (e) {
      debugPrint('[Chillz] URL check failed (ignoring): $e');
      // Proceed to play anyway - network issues might be transient or handled by VLC
    }

    final success = await _vlc.play(url);

    if (!success) {
      setState(() {
        _status = 'error';
        _lastError = _vlc.lastError ?? 'Failed to play stream';
      });
    } else {
      // FIX: Reclaim keyboard focus for Flutter after playback starts
      _appFocusNode.requestFocus();

      // FIX 5: One-time delayed resize 300ms after play starts
      // VLC may report late dimensions, this ensures HWND is correct
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _updateVideoBounds();
      });

      // CRITICAL: Reapply volume after new stream starts
      // Volume >100% needs to be reapplied after media change
      if (_volume != 100) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            debugPrint(
                '[Chillz] Reapplying volume after stream change: ${_volume.round()}%');
            _vlc.setVolume(_volume.round());
          }
        });
      }

      // FIX: Ensure status transitions to playing even if event is missed
      Future.delayed(const Duration(seconds: 1), () async {
        if (mounted) {
          final isPlaying = await _vlc.checkIsPlaying();
          debugPrint('[Chillz] Post-play check: isPlaying=$isPlaying');
          if (isPlaying && _status != 'playing') {
            setState(() => _status = 'playing');
          }
          // Refresh tracks one more time to be sure
          await _vlc.refreshAudioTracks();
        }
      });
    }
  }

  Future<void> _retry() async {
    if (_currentUrl.isNotEmpty) {
      // Reapply volume after retry
      final savedVolume = _volume;
      await _startPlayback(_currentUrl);
      if (savedVolume != 100) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) _vlc.setVolume(savedVolume.round());
        });
      }
    }
  }

  Future<void> _playPause() async {
    if (_vlc.isPlaying) {
      await _vlc.pause();
    } else {
      await _vlc.resume();
    }
  }

  Future<void> _stop() async {
    await _vlc.stop();
    setState(() {
      _status = 'stopped';
    });
    // FIX: Reclaim keyboard focus after stop
    _appFocusNode.requestFocus();
  }

  Future<void> _setVolume(double v) async {
    _volume = v.clamp(0, 200);
    debugPrint(
        '[Chillz] Setting volume to: ${_volume.round()}%${_volume > 100 ? ' (BOOST)' : ''}');
    await _vlc.setVolume(_volume.round());
    setState(() {});
  }

  Future<void> _toggleMute() async {
    await _vlc.toggleMute();
    setState(() {});
  }

  Future<void> _setAudioTrack(VlcAudioTrack track) async {
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

    await _vlc.setAudioTrack(track.id);

    // CRITICAL: Reapply volume after audio track change
    // VLC may reset volume when switching tracks
    if (_volume != 100) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          debugPrint(
              '[Chillz] Reapplying volume after track change: ${_volume.round()}%');
          _vlc.setVolume(_volume.round());
        }
      });
    }

    setState(() {
      _selectedAudioTrack = track.id;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Audio: ${track.name}'),
        backgroundColor: Colors.blue.shade700,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showAudioTrackDialog() async {
    // Force refresh audio tracks first
    await _vlc.refreshAudioTracks();

    // Update local state from VLC
    setState(() {
      _audioTracks = _vlc.audioTracks;
      _selectedAudioTrack = _vlc.currentAudioTrack;
    });

    debugPrint('[Chillz] Audio tracks available: ${_audioTracks.length}');

    if (_audioTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No audio tracks available'),
          backgroundColor: Colors.grey.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // CRITICAL: Hide video HWND so dialog appears on top
    _vlc.hideVideo();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.audiotrack, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('Audio Tracks (VLC)'),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_devMode)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${_audioTracks.length} tracks available',
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                ),
              ListView.builder(
                shrinkWrap: true,
                itemCount: _audioTracks.length,
                itemBuilder: (context, index) {
                  final track = _audioTracks[index];
                  final isSelected = _selectedAudioTrack == track.id;
                  final isFailed = _failedAudioTracks.contains(track.id);

                  return Card(
                    elevation: isSelected ? 3 : 1,
                    color: isFailed
                        ? Colors.grey.shade800.withOpacity(0.5)
                        : isSelected
                            ? Colors.blue.withOpacity(0.15)
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
                        track.name,
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
                              _setAudioTrack(track);
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
    ).then((_) {
      // CRITICAL: Show video HWND after dialog closes
      _vlc.showVideo();
      _appFocusNode.requestFocus(); // Reclaim keyboard focus
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
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
      case LogicalKeyboardKey.keyM:
        _toggleMute();
        break;
      case LogicalKeyboardKey.arrowUp:
        _setVolume(_volume + 10);
        break;
      case LogicalKeyboardKey.arrowDown:
        _setVolume(_volume - 10);
        break;
      // VLC-style bracket keys for volume (0-200%)
      case LogicalKeyboardKey.bracketRight:
        _setVolume(_volume + 10);
        break;
      case LogicalKeyboardKey.bracketLeft:
        _setVolume(_volume - 10);
        break;
      case LogicalKeyboardKey.keyR:
        _retry();
        break;
      case LogicalKeyboardKey.keyS:
        _stop();
        break;
      case LogicalKeyboardKey.escape:
        if (_isFullscreen) {
          _toggleFullscreen();
        }
        break;
    }
  }

  void _updateSearch(String query) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = query.trim().toLowerCase();
      });
    });
  }

  /// Searchable filter dropdown with typeahead
  Widget _buildSearchableFilter({
    required String label,
    required String value,
    required List<Map<String, String?>> items,
    required String idKey,
    required String nameKey,
    required String filterText,
    required void Function(String) onFilterChanged,
    required void Function(String) onSelected,
    required FocusNode focusNode, // Pass focus node for tracking
  }) {
    // Filter items based on search text - NOT USED, kept for compatibility
    final filteredItems = filterText.isEmpty
        ? items
        : items.where((item) {
            final name = (item[nameKey] ?? '').toLowerCase();
            return name.contains(filterText.toLowerCase());
          }).toList();

    // Find current selection name
    final currentItem = items.firstWhere(
      (item) => item[idKey] == value,
      orElse: () => {idKey: 'all', nameKey: label},
    );
    final currentName = currentItem[nameKey] ?? label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label with current selection
        Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            if (value != 'all') ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  currentName,
                  style: const TextStyle(fontSize: 10, color: Colors.blue),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => onSelected('all'),
                child: Icon(Icons.close, size: 14, color: Colors.grey[500]),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        // Search field with dropdown - USE PROVIDED FOCUS NODE
        SizedBox(
          height: 36,
          child: Autocomplete<Map<String, String?>>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              onFilterChanged(textEditingValue.text);
              if (textEditingValue.text.isEmpty) {
                return items; // Show ALL items when empty
              }
              return items.where((item) {
                final name = (item[nameKey] ?? '').toLowerCase();
                return name.contains(textEditingValue.text.toLowerCase());
              }); // Show ALL matching results
            },
            displayStringForOption: (item) => item[nameKey] ?? '',
            onSelected: (item) {
              onSelected(item[idKey] ?? 'all');
              // Clear focus after selection to prevent shortcuts being blocked
              focusNode.unfocus();
            },
            fieldViewBuilder:
                (context, controller, autocompleteFocusNode, onFieldSubmitted) {
              // Sync focus state with our tracked focus node
              autocompleteFocusNode.addListener(() {
                if (autocompleteFocusNode.hasFocus != focusNode.hasFocus) {
                  if (autocompleteFocusNode.hasFocus) {
                    focusNode.requestFocus();
                  }
                  // Update the text field focus state
                  _onTextFieldFocusChange();
                }
              });
              return TextField(
                controller: controller,
                focusNode: autocompleteFocusNode,
                onTap: () {
                  // Mark as focused when tapped
                  setState(() => _isTextFieldFocused = true);
                },
                onEditingComplete: () {
                  // Clear focus when done editing
                  autocompleteFocusNode.unfocus();
                  setState(() => _isTextFieldFocused = false);
                },
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: value == 'all' ? 'All $label' : currentName,
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: value == 'all' ? Colors.grey[500] : Colors.white70,
                  ),
                  prefixIcon: Icon(
                    label == 'Category'
                        ? Icons.category
                        : label == 'Country'
                            ? Icons.flag
                            : Icons.language,
                    size: 18,
                    color: Colors.grey[600],
                  ),
                  suffixIcon: controller.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            controller.clear();
                            onFilterChanged('');
                          },
                          child: Icon(Icons.clear,
                              size: 16, color: Colors.grey[500]),
                        )
                      : Icon(Icons.arrow_drop_down, color: Colors.grey[500]),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.grey.shade700),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.grey.shade700),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        const BorderSide(color: Colors.blue, width: 1.5),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade900,
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8,
                  color: const Color(0xFF1E2732),
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: 350, maxWidth: 320),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final item = options.elementAt(index);
                        final isSelected = item[idKey] == value;
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          selected: isSelected,
                          selectedTileColor: Colors.blue.withOpacity(0.2),
                          leading: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            size: 16,
                            color: isSelected ? Colors.blue : Colors.grey[600],
                          ),
                          title: Text(
                            item[nameKey] ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              color: isSelected ? Colors.blue : Colors.white,
                            ),
                          ),
                          onTap: () => onSelected(item),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                onPressed: () => iptv.loadChannels(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Search box
          TextField(
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search channels...',
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade700),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (v) {
              // Debounce search to prevent UI blocking
              _searchTimer?.cancel();
              _searchTimer = Timer(const Duration(milliseconds: 300), () {
                if (mounted) {
                  setState(() {
                    _search = v.trim();
                    _filterDirty = true;
                    _currentPage = 0; // Reset pagination on search
                  });
                }
              });
            },
          ),
          const SizedBox(height: 8),

          // Filters - Searchable dropdowns
          _buildSearchableFilter(
            label: 'Category',
            value: _selectedCategory,
            items: [
              {'id': 'all', 'name': 'All Categories'},
              ...iptv.getUniqueCategories()
            ],
            idKey: 'id',
            nameKey: 'name',
            filterText: _categoryFilter,
            onFilterChanged: (v) => setState(() => _categoryFilter = v),
            onSelected: (v) => setState(() {
              _selectedCategory = v;
              _categoryFilter = '';
              _filterDirty = true;
              _currentPage = 0; // Reset pagination
            }),
            focusNode: _categoryFilterFocusNode,
          ),
          const SizedBox(height: 6),
          _buildSearchableFilter(
            label: 'Country',
            value: _selectedCountry,
            items: [
              {'code': 'all', 'name': 'All Countries'},
              ...iptv.getUniqueCountries()
            ],
            idKey: 'code',
            nameKey: 'name',
            filterText: _countryFilter,
            onFilterChanged: (v) => setState(() => _countryFilter = v),
            onSelected: (v) => setState(() {
              _selectedCountry = v;
              _countryFilter = '';
              _filterDirty = true;
              _currentPage = 0; // Reset pagination
            }),
            focusNode: _countryFilterFocusNode,
          ),
          const SizedBox(height: 6),
          _buildSearchableFilter(
            label: 'Language',
            value: _selectedLanguage,
            items: [
              {'code': 'all', 'name': 'All Languages'},
              ...iptv.getUniqueLanguages()
            ],
            idKey: 'code',
            nameKey: 'name',
            filterText: _languageFilter,
            onFilterChanged: (v) => setState(() => _languageFilter = v),
            onSelected: (v) => setState(() {
              _selectedLanguage = v;
              _languageFilter = '';
              _filterDirty = true;
              _currentPage = 0; // Reset pagination
            }),
            focusNode: _languageFilterFocusNode,
          ),
          const SizedBox(height: 8),

          // Channel list
          Expanded(
            child: _buildChannelList(iptv),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelList(IptvService iptv) {
    // OPTIMIZATION: Only recompute filtered list when filter changes
    if (_filterDirty || _filteredChannels.isEmpty) {
      final searchLower = _search.toLowerCase();

      _filteredChannels = iptv.channels.where((ch) {
        // Search filter
        if (_search.isNotEmpty) {
          final matchesSearch = ch.name.toLowerCase().contains(searchLower) ||
              ch.countryName.toLowerCase().contains(searchLower) ||
              ch.categoryName.toLowerCase().contains(searchLower) ||
              ch.languageNames
                  .any((l) => l.toLowerCase().contains(searchLower));
          if (!matchesSearch) return false;
        }

        // Category filter
        if (_selectedCategory != 'all') {
          if (ch.category.toLowerCase() != _selectedCategory.toLowerCase())
            return false;
        }

        // Country filter
        if (_selectedCountry != 'all') {
          if (ch.country.toLowerCase() != _selectedCountry.toLowerCase())
            return false;
        }

        // Language filter
        if (_selectedLanguage != 'all') {
          final hasLang = ch.languages
              .any((l) => l.toLowerCase() == _selectedLanguage.toLowerCase());
          if (!hasLang) return false;
        }

        return true;
      }).toList();

      _filterDirty = false;
    }

    final filtered = _filteredChannels;

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 8),
            Text('No channels match',
                style: TextStyle(color: Colors.grey[400])),
          ],
        ),
      );
    }

    // PAGINATION: Calculate displayed items
    final totalItems = filtered.length;
    final displayCount = ((_currentPage + 1) * _pageSize).clamp(0, totalItems);
    final hasMore = displayCount < totalItems;

    return Column(
      children: [
        // Channel count & pagination info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Text(
                'Showing $displayCount of $totalItems',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const Spacer(),
              if (_currentPage > 0)
                TextButton(
                  onPressed: () => setState(() => _currentPage = 0),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reset', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
        // Channel list (virtualized)
        Expanded(
          child: ListView.builder(
            // Virtualized ListView - only renders visible items
            itemCount: displayCount + (hasMore ? 1 : 0),
            cacheExtent: 100, // Pre-render 100 pixels worth of items
            itemBuilder: (context, i) {
              // "Load More" button at the end
              if (i >= displayCount) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  child: _isLoadingMore
                      ? const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: _loadMoreChannels,
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(
                            'Load ${(totalItems - displayCount).clamp(0, _pageSize)} more',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                          ),
                        ),
                );
              }

              final ch = filtered[i];
              return ListTile(
                leading: ch.logo.isNotEmpty
                    ? Image.network(
                        ch.logo,
                        width: 36,
                        height: 24,
                        fit: BoxFit.cover,
                        // FIX: Silent error handling for network images
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.tv, size: 24),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const SizedBox(
                            width: 36,
                            height: 24,
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        },
                      )
                    : const Icon(Icons.tv, size: 24),
                title: Text(ch.name),
                subtitle: Text(
                  '${ch.countryFlag} ${ch.countryName} • ${ch.categoryName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  _urlController.text = ch.url;
                  _startPlayback(ch.url);
                },
              );
            },
          ),
        ),
      ],
    );
  }

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

  Widget _buildVideoArea() {
    // VLC renders to native window - Flutter shows status overlays
    Widget content;

    if (_status == 'idle' || _status == 'ready') {
      content = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tv, size: 64, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              'Direct libVLC Integration\nClick a channel to play',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            SizedBox(height: 8),
            Text(
              'We do the hard stuff just chill',
              style: TextStyle(color: Colors.green, fontSize: 12),
            ),
          ],
        ),
      );
    } else if (_status == 'switching' || _status == 'loading') {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.cyan),
            const SizedBox(height: 16),
            Text(
              _status == 'switching' ? 'Switching channel...' : 'Loading...',
              style: TextStyle(color: Colors.cyan),
            ),
          ],
        ),
      );
    } else if (_status == 'buffering') {
      content = Stack(
        children: [
          // VLC video renders here natively
          Container(color: Colors.black),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.yellow),
                const SizedBox(height: 16),
                const Text('Buffering...',
                    style: TextStyle(color: Colors.yellow)),
              ],
            ),
          ),
        ],
      );
    } else if (_status == 'error' || _status == 'unavailable') {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              _status == 'unavailable'
                  ? 'Stream Unavailable'
                  : _lastError.contains('403') ||
                          _lastError.toLowerCase().contains('forbidden')
                      ? 'Access Restricted (Geo-blocked/403)'
                      : _lastError.contains('404') ||
                              _lastError.toLowerCase().contains('not found')
                          ? 'Stream Not Found (404)'
                          : _lastError.contains('401') ||
                                  _lastError
                                      .toLowerCase()
                                      .contains('unauthorized')
                              ? 'Unauthorized Access (401)'
                              : _lastError.contains('400') ||
                                      _lastError
                                          .toLowerCase()
                                          .contains('bad request')
                                  ? 'Bad Request (400)'
                                  : 'Playback Error',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            if (_lastError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                  _lastError.contains('403')
                      ? 'This channel requires a different IP or token.'
                      : _lastError.contains('404')
                          ? 'This channel is currently offline.'
                          : _lastError.contains('400')
                              ? 'Invalid stream request (Token expired?)'
                              : _lastError,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700),
            ),
          ],
        ),
      );
    } else {
      // Playing - VLC renders video natively
      // This container receives the native video surface
      content = Container(
        color: Colors.black,
        child: Stack(
          children: [
            // Native VLC video renders to this surface
            // On Windows, VLC uses HWND for rendering
            const Center(
              child: Text(
                'VLC Video Surface\n(Native rendering)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white30, fontSize: 12),
              ),
            ),
            // Status overlay
            if (_vlc.isPlaying)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('VLC Playing',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            // Fullscreen toggle button
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: _toggleFullscreen,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            // Enhanced Debug Overlay
            if (_devMode)
              Positioned(
                bottom: 12,
                left: 12,
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85),
                    border: Border.all(color: Colors.amber.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bug_report,
                              color: Colors.amber, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'DEV MODE - Direct libVLC',
                              style: TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          // Copy error button
                          if (_lastError.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.copy,
                                  size: 14, color: Colors.white70),
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: _lastError));
                              },
                              tooltip: 'Copy Error',
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                            ),
                        ],
                      ),
                      const Divider(height: 12, color: Colors.white24),
                      SelectableText.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                                text: 'Status: ',
                                style: TextStyle(color: Colors.grey)),
                            TextSpan(
                                text: '$_status (${_vlc.state.name})\n',
                                style: TextStyle(
                                    color: _status == 'error'
                                        ? Colors.red
                                        : Colors.green)),
                            const TextSpan(
                                text: 'URL: ',
                                style: TextStyle(color: Colors.grey)),
                            TextSpan(
                                text: '${_currentUrl.split('/').last}\n',
                                style: const TextStyle(color: Colors.white70)),
                            if (_lastError.isNotEmpty) ...[
                              const TextSpan(
                                  text: 'Error: ',
                                  style: TextStyle(color: Colors.red)),
                              TextSpan(
                                  text: '$_lastError\n',
                                  style:
                                      const TextStyle(color: Colors.redAccent)),
                            ],
                            const TextSpan(
                                text: 'Audio: ',
                                style: TextStyle(color: Colors.grey)),
                            TextSpan(
                                text:
                                    '${_audioTracks.length} tracks | Selected: $_selectedAudioTrack\n',
                                style: const TextStyle(color: Colors.white70)),
                            const TextSpan(
                                text: 'Resolution: ',
                                style: TextStyle(color: Colors.grey)),
                            TextSpan(
                                text:
                                    '${_vlc.videoWidth}x${_vlc.videoHeight}\n',
                                style: const TextStyle(color: Colors.white70)),
                            const TextSpan(
                                text: 'Volume: ',
                                style: TextStyle(color: Colors.grey)),
                            TextSpan(
                                text: '$_volume | Muted: ${_vlc.isMuted}\n',
                                style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'Consolas', height: 1.3),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // CRITICAL: Wrap in Container with GlobalKey for accurate layout extraction
    // Wrap with GestureDetector to reclaim focus when video area is clicked
    return GestureDetector(
      onTap: () {
        // Reclaim keyboard focus when video area is clicked
        _appFocusNode.requestFocus();
        debugPrint('[Chillz] Video area clicked - focus reclaimed');
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: _videoContainerKey,
        margin: _isFullscreen ? EdgeInsets.zero : const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius:
              _isFullscreen ? BorderRadius.zero : BorderRadius.circular(8),
          border:
              _isFullscreen ? null : Border.all(color: Colors.grey.shade800),
        ),
        child: ClipRRect(
          borderRadius:
              _isFullscreen ? BorderRadius.zero : BorderRadius.circular(8),
          child: content,
        ),
      ),
    );
  }

  Widget _buildControls() {
    // Guard: Don't render controls until VLC service is ready
    if (!_vlcServiceReady) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF0B1220), const Color(0xFF1a2332)],
        ),
        border: Border(top: BorderSide(color: Colors.white24)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Play/Pause
              _buildControlButton(
                icon: _vlc.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.blue,
                onPressed: _playPause,
                tooltip: 'Play/Pause (Space)',
              ),
              const SizedBox(width: 8),

              // Stop
              _buildControlButton(
                icon: Icons.stop,
                color: Colors.red,
                onPressed: _stop,
                tooltip: 'Stop (S)',
              ),
              const SizedBox(width: 8),

              // Retry
              _buildControlButton(
                icon: Icons.refresh,
                color: Colors.orange,
                onPressed: _retry,
                tooltip: 'Retry (R)',
              ),
              const SizedBox(width: 16),

              // Audio tracks
              _buildControlButton(
                icon: Icons.audiotrack,
                color: _audioTracks.isNotEmpty ? Colors.purple : Colors.grey,
                onPressed:
                    _showAudioTrackDialog, // Always enabled so user can re-scan/check
                tooltip: 'Audio Track (A)',
              ),
              const SizedBox(width: 16),

              // Volume
              Tooltip(
                message:
                    _volume > 100 ? 'BOOST: May cause distortion' : 'Volume',
                child: Icon(
                  _volume > 100
                      ? Icons.volume_up
                      : (_volume > 0 ? Icons.volume_up : Icons.volume_off),
                  color: _volume > 100 ? Colors.orange : Colors.white70,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: _volume > 100
                      ? 'Volume: ${_volume.round()}% (BOOST - may distort)'
                      : 'Volume: ${_volume.round()}%',
                  child: Slider(
                    value: _volume,
                    min: 0,
                    max: 200,
                    divisions: 40,
                    onChanged: _setVolume,
                    activeColor: _volume > 100 ? Colors.orange : Colors.blue,
                    inactiveColor: Colors.grey[700],
                  ),
                ),
              ),
              Text(
                _volume > 100 ? '${_volume.round()}% ⚡' : '${_volume.round()}%',
                style: TextStyle(
                  color: _volume > 100 ? Colors.orange : Colors.grey[400],
                  fontSize: 12,
                  fontWeight:
                      _volume > 100 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 8),

              // Mute
              _buildControlButton(
                icon: _vlc.isMuted ? Icons.volume_off : Icons.volume_up,
                color: _vlc.isMuted ? Colors.red : Colors.white70,
                onPressed: _toggleMute,
                tooltip: 'Mute (M)',
              ),
              const SizedBox(width: 8),
              // Fullscreen button placed to the right of the speaker button
              _buildControlButton(
                icon: _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white70,
                onPressed: _toggleFullscreen,
                tooltip: 'Fullscreen (F)',
              ),
            ],
          ),

          // Shortcuts info
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildShortcutChip('Space', 'Play/Pause'),
              _buildShortcutChip('F', 'Fullscreen'),
              _buildShortcutChip('Esc', 'Exit FS'),
              _buildShortcutChip('S', 'Stop'),
              _buildShortcutChip('A', 'Audio'),
              _buildShortcutChip('M', 'Mute'),
              _buildShortcutChip('R', 'Retry'),
              _buildShortcutChip('↑/↓', 'Vol'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    VoidCallback? onPressed,
    String? tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(onPressed != null ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: onPressed != null ? color : Colors.grey),
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildShortcutChip(String key, String action) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$key: $action',
        style: TextStyle(color: Colors.grey[300], fontSize: 10),
      ),
    );
  }

  Widget _buildStatusBar() {
    final iptv = Provider.of<IptvService>(context);

    Color statusColor = Colors.white70;
    String statusText = _status;

    switch (_status) {
      case 'playing':
        statusColor = Colors.green;
        statusText = 'Playing (VLC)';
        break;
      case 'buffering':
      case 'loading':
      case 'switching':
        statusColor = Colors.yellow;
        break;
      case 'error':
      case 'unavailable':
        statusColor = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF071019),
      child: Row(
        children: [
          if (statusText.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.2),
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

          // VLC badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'libVLC',
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(width: 12),

          Text('${iptv.channels.length} channels',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),

          const SizedBox(width: 12),

          // Dev mode toggle
          GestureDetector(
            onTap: () => setState(() => _devMode = !_devMode),
            child: Icon(
              Icons.bug_report,
              size: 14,
              color: _devMode ? Colors.orange : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevPanel() {
    if (!_devMode) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black.withOpacity(0.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DEV MODE - Direct libVLC',
              style: TextStyle(
                  color: Colors.orange,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (_currentUrl.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: _currentUrl));
                }
              },
              child: Text(
                'URL: ${_currentUrl.isEmpty ? '—' : _currentUrl}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
          Text('VLC State: ${_vlc.state} | Initialized: ${_vlc.initialized}',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(
              'Audio Tracks: ${_audioTracks.length} | Current: $_selectedAudioTrack',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text('Volume: ${_vlc.volume} | Muted: ${_vlc.isMuted}',
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
    // In fullscreen mode, show only the video
    if (_isFullscreen) {
      // Use RawKeyboardListener for more reliable keyboard capture
      return RawKeyboardListener(
        focusNode: _appFocusNode,
        autofocus: true,
        onKey: (RawKeyEvent event) {
          if (event is RawKeyDownEvent) {
            // ESC key - HIGHEST PRIORITY
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _toggleFullscreen();
              return;
            }
            // Other shortcuts (only if not in text field)
            if (!_isTextFieldFocused) {
              _handleKeyEvent(KeyDownEvent(
                physicalKey: event.physicalKey,
                logicalKey: event.logicalKey,
                character: event.character,
                timeStamp: Duration.zero,
              ));
            }
          }
        },
        child: GestureDetector(
          onTap: () =>
              _appFocusNode.requestFocus(), // Ensure focus for keyboard
          behavior: HitTestBehavior.opaque, // Capture all taps
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                Positioned.fill(child: _buildVideoArea()),
                // Minimal controls overlay in fullscreen
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: MouseRegion(
                    child: AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.8),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(
                                _vlc.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: _playPause,
                            ),
                            IconButton(
                              icon: const Icon(Icons.stop, color: Colors.white),
                              onPressed: _stop,
                            ),
                            const SizedBox(width: 16),
                            Tooltip(
                              message: _volume > 100
                                  ? 'BOOST: ${_volume.round()}%'
                                  : 'Volume',
                              child: Icon(Icons.volume_up,
                                  color: _volume > 100
                                      ? Colors.orange
                                      : Colors.white70,
                                  size: 20),
                            ),
                            SizedBox(
                              width: 100,
                              child: Slider(
                                value: _volume,
                                min: 0,
                                max: 200,
                                onChanged: _setVolume,
                                activeColor: _volume > 100
                                    ? Colors.orange
                                    : Colors.white,
                                inactiveColor: Colors.grey,
                              ),
                            ),
                            if (_volume > 100)
                              Text(
                                '${_volume.round()}%⚡',
                                style: const TextStyle(
                                    color: Colors.orange, fontSize: 11),
                              ),
                            const SizedBox(width: 16),
                            IconButton(
                              icon: const Icon(Icons.fullscreen_exit,
                                  color: Colors.white),
                              onPressed: _toggleFullscreen,
                              tooltip: 'Exit Fullscreen (F or Esc)',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Normal (non-fullscreen) mode - Use RawKeyboardListener for consistent keyboard capture
    return RawKeyboardListener(
      focusNode: _appFocusNode,
      autofocus: true,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent && !_isTextFieldFocused) {
          _handleKeyEvent(KeyDownEvent(
            physicalKey: event.physicalKey,
            logicalKey: event.logicalKey,
            character: event.character,
            timeStamp: Duration.zero,
          ));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Icon(Icons.tv, color: Colors.orange),
              const SizedBox(width: 8),
              const Text('Chillz TV'),
            ],
          ),
          backgroundColor: const Color(0xFF1a2332),
        ),
        body: Row(
          children: [
            _buildLeftPanel(),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _buildVideoArea()),
                  _buildControls(),
                  _buildStatusBar(),
                  _buildDevPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
