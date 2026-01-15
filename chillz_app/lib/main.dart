// Chillz App - Cross-platform IPTV Player
// Platform-aware: Windows (libVLC) / Android (media_kit/MPV)
// Supports: Phone, Tablet, Android TV

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:async';
import 'package:media_kit/media_kit.dart' hide PlayerState;

import 'models/iptv_models.dart';
import 'services/iptv_service.dart';
import 'player/player_factory.dart';
import 'player/player_engine.dart';
import 'player/android_tv_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('═══════════════════════════════════════════════════════════');
  debugPrint('[Chillz] ▶ App Starting');
  debugPrint('[Chillz] Platform: ${Platform.operatingSystem}');
  debugPrint('[Chillz] Is Android: ${Platform.isAndroid}');
  debugPrint('[Chillz] Is Windows: ${Platform.isWindows}');
  debugPrint('═══════════════════════════════════════════════════════════');

  // Initialize media_kit for Android/Linux/macOS/iOS
  if (!Platform.isWindows) {
    debugPrint('[Chillz] Initializing MediaKit for non-Windows platform');
    MediaKit.ensureInitialized();
    debugPrint('[Chillz] ✓ MediaKit initialized');
  }

  // Detect Android TV
  if (Platform.isAndroid) {
    debugPrint('[Chillz] Detecting Android TV...');
    await AndroidTVUtils.init();
    PlayerFactory.setAndroidTV(AndroidTVUtils.isTV);
    debugPrint('[Chillz] Android TV mode: ${AndroidTVUtils.isTV}');

    // Force landscape for TV
    if (AndroidTVUtils.isTV) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  debugPrint('[Chillz] Creating PlayerFactory instance...');
  final player = PlayerFactory.create();
  debugPrint('[Chillz] ✓ Player created: ${player.runtimeType}');

  runApp(ChillzApp(player: player));
}

class ChillzApp extends StatelessWidget {
  final PlayerEngine player;

  const ChillzApp({Key? key, required this.player}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => IptvService()..loadChannels()),
        ChangeNotifierProvider.value(value: player),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Chillz TV',
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0F1720),
          focusColor: Colors.orange,
        ),
        home: const ChillzHome(),
      ),
    );
  }
}

class ChillzHome extends StatefulWidget {
  const ChillzHome({Key? key}) : super(key: key);

  @override
  State<ChillzHome> createState() => _ChillzHomeState();
}

class _ChillzHomeState extends State<ChillzHome> with WidgetsBindingObserver {
  late IptvService _iptvService;
  late PlayerEngine _player;
  bool _playerReady = false;

  String _currentUrl = '';
  String _status = 'idle';
  String _lastError = '';
  double _volume = 100.0;

  // Search & Filters
  String _search = '';
  String _selectedCategory = 'all';
  String _selectedCountry = 'all';
  String _selectedLanguage = 'all';
  Timer? _searchTimer;

  // Cached filtered channels
  List<Channel> _filteredChannels = [];
  bool _filterDirty = true;

  // Focus management
  final FocusNode _appFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isTextFieldFocused = false;

  // Pagination
  static const int _pageSize = 50;
  int _currentPage = 0;

  // Fullscreen state
  bool _isFullscreen = false;

  // TV mode
  bool get _isTV => AndroidTVUtils.isTV;

  // Dev mode for debugging
  bool _devMode = true;

  // GlobalKey for video container (Windows HWND positioning)
  final GlobalKey _videoContainerKey = GlobalKey();
  Rect? _lastBounds;

  // Stream subscriptions
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<PlayerError>? _errorSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    debugPrint('[ChillzHome] initState');

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializePlayer();
    });
  }

  Future<void> _initializePlayer() async {
    debugPrint('───────────────────────────────────────────────────────');
    debugPrint('[ChillzHome] ▶ Initializing player...');

    _iptvService = Provider.of<IptvService>(context, listen: false);
    _player = Provider.of<PlayerEngine>(context, listen: false);

    debugPrint('[ChillzHome] Player type: ${_player.runtimeType}');

    // Load channels if needed
    if (!_iptvService.loading && _iptvService.channels.isEmpty) {
      debugPrint('[ChillzHome] Loading IPTV channels...');
      _iptvService.loadChannels();
    }

    // Subscribe to player state changes
    _stateSubscription = _player.stateStream.listen((state) {
      debugPrint('[ChillzHome] Player state changed: $state');
      _onPlayerStateChanged(state);
    });

    _errorSubscription = _player.errorStream.listen((error) {
      debugPrint('[ChillzHome] Player error: $error');
      _onPlayerError(error);
    });

    // Initialize the player
    debugPrint('[ChillzHome] Calling player.init()...');
    final initOk = await _player.init();

    if (initOk) {
      debugPrint('[ChillzHome] ✓ Player initialized successfully');
      setState(() {
        _playerReady = true;
        _status = 'ready';
      });

      // Update video bounds for Windows
      if (Platform.isWindows) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateVideoBounds();
          });
        });
      }
    } else {
      debugPrint('[ChillzHome] ✗ Player initialization failed');
      setState(() {
        _status = 'error';
        _lastError = _player.lastError ?? 'Failed to initialize player';
      });
    }

    debugPrint('[ChillzHome] Setup complete');
    debugPrint('───────────────────────────────────────────────────────');
  }

  void _onPlayerStateChanged(PlayerState state) {
    if (!mounted) return;

    setState(() {
      switch (state) {
        case PlayerState.idle:
          _status = 'idle';
          break;
        case PlayerState.loading:
          _status = 'loading';
          break;
        case PlayerState.buffering:
          _status = 'buffering';
          break;
        case PlayerState.playing:
          _status = 'playing';
          break;
        case PlayerState.paused:
          _status = 'paused';
          break;
        case PlayerState.stopped:
          _status = 'stopped';
          break;
        case PlayerState.ended:
          _status = 'ended';
          break;
        case PlayerState.error:
          _status = 'error';
          _lastError = _player.lastError ?? 'Unknown error';
          break;
      }
      _volume = _player.volume.toDouble();
    });
  }

  void _onPlayerError(PlayerError error) {
    if (!mounted) return;

    setState(() {
      _status = 'error';
      _lastError = error.message;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.message),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _updateVideoBounds() async {
    if (!Platform.isWindows) return;
    if (!_player.isInitialized) return;

    final RenderObject? renderObject =
        _videoContainerKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;

    final RenderBox box = renderObject;
    if (!box.hasSize) return;

    final Offset globalPosition = box.localToGlobal(Offset.zero);
    final Size size = box.size;
    final double dpr = MediaQuery.of(context).devicePixelRatio;

    final int x = (globalPosition.dx * dpr).round();
    final int y = (globalPosition.dy * dpr).round();
    final int width = (size.width * dpr).round();
    final int height = (size.height * dpr).round();

    final newBounds = Rect.fromLTWH(
        x.toDouble(), y.toDouble(), width.toDouble(), height.toDouble());
    if (_lastBounds != null && _lastBounds == newBounds) return;
    _lastBounds = newBounds;

    debugPrint('[ChillzHome] Video bounds: $x, $y, $width, $height');
    await _player.setVideoBounds(x, y, width, height);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateVideoBounds();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('[ChillzHome] Lifecycle state: $state');

    if (state == AppLifecycleState.paused && _player.isPlaying) {
      _player.pause();
    } else if (state == AppLifecycleState.resumed && _status == 'paused') {
      _player.resume();
    }
  }

  @override
  void dispose() {
    debugPrint('[ChillzHome] dispose');
    WidgetsBinding.instance.removeObserver(this);
    _stateSubscription?.cancel();
    _errorSubscription?.cancel();
    _searchTimer?.cancel();
    _appFocusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _startPlayback(String url) async {
    debugPrint('[ChillzHome] Starting playback: $url');

    setState(() {
      _status = 'loading';
      _currentUrl = url;
      _lastError = '';
    });

    final success = await _player.play(url);

    if (!success) {
      setState(() {
        _status = 'error';
        _lastError = _player.lastError ?? 'Failed to play stream';
      });
    } else if (Platform.isWindows) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _updateVideoBounds();
      });
    }
  }

  Future<void> _retry() async {
    if (_currentUrl.isNotEmpty) {
      await _startPlayback(_currentUrl);
    }
  }

  Future<void> _playPause() async {
    if (_player.isPlaying) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  Future<void> _stop() async {
    await _player.stop();
    setState(() => _status = 'stopped');
  }

  Future<void> _setVolume(double v) async {
    _volume = v.clamp(0, 200);
    await _player.setVolume(_volume);
    setState(() {});
  }

  Future<void> _toggleMute() async {
    await _player.toggleMute();
    setState(() {});
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);

    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateVideoBounds());
    }

    debugPrint('[ChillzHome] Fullscreen: $_isFullscreen');
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (_isTextFieldFocused) return;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.select:
        _playPause();
        break;
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
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
      case LogicalKeyboardKey.keyR:
        _retry();
        break;
      case LogicalKeyboardKey.keyS:
        _stop();
        break;
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.goBack:
        if (_isFullscreen) _toggleFullscreen();
        break;
    }
  }

  void _updateFilters() {
    final searchLower = _search.toLowerCase();

    _filteredChannels = _iptvService.channels.where((ch) {
      if (_search.isNotEmpty) {
        final matchesSearch = ch.name.toLowerCase().contains(searchLower) ||
            ch.countryName.toLowerCase().contains(searchLower) ||
            ch.categoryName.toLowerCase().contains(searchLower);
        if (!matchesSearch) return false;
      }

      if (_selectedCategory != 'all' &&
          ch.category.toLowerCase() != _selectedCategory.toLowerCase()) {
        return false;
      }

      if (_selectedCountry != 'all' &&
          ch.country.toLowerCase() != _selectedCountry.toLowerCase()) {
        return false;
      }

      if (_selectedLanguage != 'all') {
        final hasLang = ch.languages
            .any((l) => l.toLowerCase() == _selectedLanguage.toLowerCase());
        if (!hasLang) return false;
      }

      return true;
    }).toList();

    _filterDirty = false;
  }

  @override
  Widget build(BuildContext context) {
    final iptv = Provider.of<IptvService>(context);

    if (_filterDirty || _filteredChannels.isEmpty) {
      _updateFilters();
    }

    if (_isFullscreen) {
      return _buildFullscreenMode();
    }

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
              Text(_isTV ? 'Chillz TV' : 'Chillz'),
              if (_isTV) ...[
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('TV MODE',
                      style: TextStyle(fontSize: 10, color: Colors.purple)),
                ),
              ],
            ],
          ),
          backgroundColor: const Color(0xFF1a2332),
        ),
        body: _isTV ? _buildTVLayout(iptv) : _buildMobileLayout(iptv),
      ),
    );
  }

  Widget _buildMobileLayout(IptvService iptv) {
    return Row(
      children: [
        _buildLeftPanel(iptv),
        Expanded(
          child: Column(
            children: [
              Expanded(child: _buildVideoArea()),
              _buildControls(),
              _buildStatusBar(iptv),
              if (_devMode) _buildDevPanel(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTVLayout(IptvService iptv) {
    return Row(
      children: [
        SizedBox(width: 300, child: _buildTVChannelList(iptv)),
        Expanded(
          child: Column(
            children: [
              Expanded(child: _buildVideoArea()),
              _buildTVControls(),
              if (_devMode) _buildDevPanel(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFullscreenMode() {
    return RawKeyboardListener(
      focusNode: _appFocusNode,
      autofocus: true,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack) {
            _toggleFullscreen();
            return;
          }
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
        onTap: () => _appFocusNode.requestFocus(),
        onDoubleTap: _toggleFullscreen,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(child: _buildVideoArea()),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.8),
                        Colors.transparent
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          _player.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ),
                        onPressed: _playPause,
                      ),
                      IconButton(
                        icon: const Icon(Icons.stop,
                            color: Colors.white, size: 32),
                        onPressed: _stop,
                      ),
                      const SizedBox(width: 24),
                      Icon(Icons.volume_up,
                          color:
                              _volume > 100 ? Colors.orange : Colors.white70),
                      SizedBox(
                        width: 120,
                        child: Slider(
                          value: _volume,
                          min: 0,
                          max: 200,
                          onChanged: _setVolume,
                          activeColor:
                              _volume > 100 ? Colors.orange : Colors.white,
                        ),
                      ),
                      Text('${_volume.round()}%',
                          style: TextStyle(
                              color: _volume > 100
                                  ? Colors.orange
                                  : Colors.white)),
                      const SizedBox(width: 24),
                      IconButton(
                        icon: const Icon(Icons.fullscreen_exit,
                            color: Colors.white, size: 32),
                        onPressed: _toggleFullscreen,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPanel(IptvService iptv) {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
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
                onPressed: () {
                  _filterDirty = true;
                  iptv.loadChannels(forceRefresh: true);
                },
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search channels...',
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.blue, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade700),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (v) {
              _searchTimer?.cancel();
              _searchTimer = Timer(const Duration(milliseconds: 300), () {
                if (mounted) {
                  setState(() {
                    _search = v.trim();
                    _filterDirty = true;
                    _currentPage = 0;
                  });
                }
              });
            },
            onTap: () => setState(() => _isTextFieldFocused = true),
            onEditingComplete: () =>
                setState(() => _isTextFieldFocused = false),
          ),
          const SizedBox(height: 8),
          _buildFilterDropdown(
            label: 'Category',
            value: _selectedCategory,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All Category')),
              ...iptv.getUniqueCategories().map((c) => DropdownMenuItem(
                    value: c['id'],
                    child: Text(c['name'] ?? 'Unknown'),
                  )),
            ],
            onChanged: (v) {
              setState(() {
                _selectedCategory = v ?? 'all';
                _filterDirty = true;
                _currentPage = 0;
              });
            },
          ),
          const SizedBox(height: 6),
          _buildFilterDropdown(
            label: 'Country',
            value: _selectedCountry,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All Country')),
              ...iptv.getUniqueCountries().map((c) => DropdownMenuItem(
                    value: c['code'],
                    child: Text(c['name'] ?? 'Unknown'),
                  )),
            ],
            onChanged: (v) {
              setState(() {
                _selectedCountry = v ?? 'all';
                _filterDirty = true;
                _currentPage = 0;
              });
            },
          ),
          const SizedBox(height: 6),
          _buildFilterDropdown(
            label: 'Language',
            value: _selectedLanguage,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All Language')),
              ...iptv.getUniqueLanguages().map((c) => DropdownMenuItem(
                    value: c['code'],
                    child: Text(c['name'] ?? 'Unknown'),
                  )),
            ],
            onChanged: (v) {
              setState(() {
                _selectedLanguage = v ?? 'all';
                _filterDirty = true;
                _currentPage = 0;
              });
            },
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildChannelList()),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: DropdownButtonFormField<String>(
            value: value,
            items: items,
            onChanged: onChanged,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              filled: true,
              fillColor: Colors.grey.shade900,
            ),
            dropdownColor: const Color(0xFF1E2732),
            isExpanded: true,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildChannelList() {
    if (_filteredChannels.isEmpty) {
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

    final totalItems = _filteredChannels.length;
    final displayCount = ((_currentPage + 1) * _pageSize).clamp(0, totalItems);
    final hasMore = displayCount < totalItems;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'Showing $displayCount of $totalItems',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: displayCount + (hasMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= displayCount) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: () => setState(() => _currentPage++),
                    child: Text(
                        'Load more (${totalItems - displayCount} remaining)'),
                  ),
                );
              }

              final ch = _filteredChannels[i];
              return ListTile(
                leading: ch.logo.isNotEmpty
                    ? Image.network(
                        ch.logo,
                        width: 36,
                        height: 24,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.tv, size: 24),
                      )
                    : const Icon(Icons.tv, size: 24),
                title: Text(ch.name),
                subtitle: Text(
                  '${ch.countryFlag} ${ch.countryName} • ${ch.categoryName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _startPlayback(ch.url),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTVChannelList(IptvService iptv) {
    if (_filterDirty || _filteredChannels.isEmpty) {
      _updateFilters();
    }

    return FocusTraversalGroup(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              style: const TextStyle(fontSize: 18),
              onChanged: (v) {
                setState(() {
                  _search = v.trim();
                  _filterDirty = true;
                });
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredChannels.length.clamp(0, 100),
              itemBuilder: (context, i) {
                final ch = _filteredChannels[i];
                return _TVFocusableItem(
                  onTap: () => _startPlayback(ch.url),
                  child: ListTile(
                    leading: ch.logo.isNotEmpty
                        ? Image.network(
                            ch.logo,
                            width: 48,
                            height: 32,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.tv, size: 32),
                          )
                        : const Icon(Icons.tv, size: 32),
                    title: Text(ch.name, style: const TextStyle(fontSize: 18)),
                    subtitle: Text('${ch.countryFlag} ${ch.countryName}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoArea() {
    Widget content;

    if (_status == 'idle' || _status == 'ready') {
      content = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tv, size: 64, color: Colors.white24),
            SizedBox(height: 16),
            Text('Select a channel to play',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    } else if (_status == 'loading') {
      content = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.cyan),
            SizedBox(height: 16),
            Text('Loading...', style: TextStyle(color: Colors.cyan)),
          ],
        ),
      );
    } else if (_status == 'buffering') {
      content = Stack(
        children: [
          if (_playerReady) _player.buildVideoWidget(),
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.yellow),
                SizedBox(height: 16),
                Text('Buffering...', style: TextStyle(color: Colors.yellow)),
              ],
            ),
          ),
        ],
      );
    } else if (_status == 'error') {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Playback Error',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            if (_lastError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_lastError,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    } else {
      content = _playerReady
          ? _player.buildVideoWidget(fit: BoxFit.contain)
          : Container(color: Colors.black);
    }

    return Container(
      key: _videoContainerKey,
      margin: _isFullscreen ? EdgeInsets.zero : const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius:
            _isFullscreen ? BorderRadius.zero : BorderRadius.circular(8),
        border: _isFullscreen ? null : Border.all(color: Colors.grey.shade800),
      ),
      child: ClipRRect(
        borderRadius:
            _isFullscreen ? BorderRadius.zero : BorderRadius.circular(8),
        child: content,
      ),
    );
  }

  Widget _buildControls() {
    if (!_playerReady) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        gradient:
            LinearGradient(colors: [Color(0xFF0B1220), Color(0xFF1a2332)]),
        border: Border(top: BorderSide(color: Colors.white24)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildControlButton(
                icon: _player.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.blue,
                onPressed: _playPause,
                tooltip: 'Play/Pause (Space)',
              ),
              const SizedBox(width: 8),
              _buildControlButton(
                  icon: Icons.stop,
                  color: Colors.red,
                  onPressed: _stop,
                  tooltip: 'Stop (S)'),
              const SizedBox(width: 8),
              _buildControlButton(
                  icon: Icons.refresh,
                  color: Colors.orange,
                  onPressed: _retry,
                  tooltip: 'Retry (R)'),
              const SizedBox(width: 16),
              Tooltip(
                message: _volume > 100 ? 'BOOST' : 'Volume',
                child: Icon(
                  _volume > 100
                      ? Icons.volume_up
                      : (_volume > 0 ? Icons.volume_up : Icons.volume_off),
                  color: _volume > 100 ? Colors.orange : Colors.white70,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _volume,
                  min: 0,
                  max: 200,
                  divisions: 40,
                  onChanged: _setVolume,
                  activeColor: _volume > 100 ? Colors.orange : Colors.blue,
                ),
              ),
              Text(
                _volume > 100 ? '${_volume.round()}% ⚡' : '${_volume.round()}%',
                style: TextStyle(
                    color: _volume > 100 ? Colors.orange : Colors.grey[400],
                    fontSize: 12),
              ),
              const SizedBox(width: 8),
              _buildControlButton(
                icon: _player.isMuted ? Icons.volume_off : Icons.volume_up,
                color: _player.isMuted ? Colors.red : Colors.white70,
                onPressed: _toggleMute,
                tooltip: 'Mute (M)',
              ),
              const SizedBox(width: 8),
              _buildControlButton(
                icon: _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white70,
                onPressed: _toggleFullscreen,
                tooltip: 'Fullscreen (F)',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildShortcutChip('Space', 'Play/Pause'),
              _buildShortcutChip('F', 'Fullscreen'),
              _buildShortcutChip('Esc', 'Exit FS'),
              _buildShortcutChip('S', 'Stop'),
              _buildShortcutChip('M', 'Mute'),
              _buildShortcutChip('R', 'Retry'),
              _buildShortcutChip('↑/↓', 'Vol'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTVControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF0B1220),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TVFocusableItem(
            onTap: _playPause,
            child: Icon(
                _player.isPlaying ? Icons.pause_circle : Icons.play_circle,
                size: 48,
                color: Colors.blue),
          ),
          const SizedBox(width: 24),
          _TVFocusableItem(
              onTap: _stop,
              child:
                  const Icon(Icons.stop_circle, size: 48, color: Colors.red)),
          const SizedBox(width: 24),
          _TVFocusableItem(
              onTap: () => _setVolume(_volume - 10),
              child: const Icon(Icons.volume_down, size: 48)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('${_volume.round()}%',
                style: const TextStyle(fontSize: 20)),
          ),
          _TVFocusableItem(
              onTap: () => _setVolume(_volume + 10),
              child: const Icon(Icons.volume_up, size: 48)),
          const SizedBox(width: 24),
          _TVFocusableItem(
              onTap: _toggleFullscreen,
              child: const Icon(Icons.fullscreen, size: 48)),
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
          color: Colors.grey[800], borderRadius: BorderRadius.circular(4)),
      child: Text('$key: $action',
          style: TextStyle(color: Colors.grey[300], fontSize: 10)),
    );
  }

  Widget _buildStatusBar(IptvService iptv) {
    Color statusColor = Colors.white70;
    String statusText = _status;

    switch (_status) {
      case 'playing':
        statusColor = Colors.green;
        statusText = 'Playing';
        break;
      case 'buffering':
      case 'loading':
        statusColor = Colors.yellow;
        break;
      case 'error':
        statusColor = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF071019),
      child: Row(
        children: [
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
                        color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(statusText,
                    style: TextStyle(fontSize: 12, color: statusColor)),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Platform.isWindows
                  ? Colors.orange.withOpacity(0.2)
                  : Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              Platform.isWindows ? 'libVLC' : 'MPV',
              style: TextStyle(
                fontSize: 10,
                color: Platform.isWindows ? Colors.orange : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('${iptv.channels.length} channels',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() => _devMode = !_devMode),
            child: Icon(Icons.bug_report,
                size: 14,
                color: _devMode ? Colors.orange : Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildDevPanel() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black.withOpacity(0.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DEV MODE - ${Platform.isWindows ? "libVLC" : "media_kit/MPV"}',
            style: const TextStyle(
                color: Colors.orange,
                fontSize: 10,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('Platform: ${Platform.operatingSystem} | TV: $_isTV',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text('Player: ${_player.runtimeType} | Ready: $_playerReady',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text('State: ${_player.state} | Playing: ${_player.isPlaying}',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text('URL: ${_currentUrl.isEmpty ? "—" : _currentUrl}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text('Volume: ${_player.volume} | Muted: ${_player.isMuted}',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          if (_lastError.isNotEmpty)
            Text('Error: $_lastError',
                style:
                    const TextStyle(fontSize: 10, color: Colors.orangeAccent)),
        ],
      ),
    );
  }
}

class _TVFocusableItem extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _TVFocusableItem({required this.child, required this.onTap});

  @override
  State<_TVFocusableItem> createState() => _TVFocusableItemState();
}

class _TVFocusableItemState extends State<_TVFocusableItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            border:
                _isFocused ? Border.all(color: Colors.orange, width: 3) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
