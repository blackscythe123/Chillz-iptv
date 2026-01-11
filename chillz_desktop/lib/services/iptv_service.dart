import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/iptv_models.dart';

/// Data transfer object for compute isolate
class _ProcessingData {
  final String channelsJson;
  final String streamsJson;
  final String logosJson;
  final String categoriesJson;
  final String countriesJson;
  final String languagesJson;

  _ProcessingData({
    required this.channelsJson,
    required this.streamsJson,
    required this.logosJson,
    required this.categoriesJson,
    required this.countriesJson,
    required this.languagesJson,
  });
}

/// Process channel data in a background isolate to prevent UI blocking
List<Channel> _processChannelsInIsolate(_ProcessingData data) {
  // Parse JSON
  final chRaw = jsonDecode(data.channelsJson) as List<dynamic>;
  final stRaw = jsonDecode(data.streamsJson) as List<dynamic>;
  final lgRaw = jsonDecode(data.logosJson) as List<dynamic>;
  final catRaw = jsonDecode(data.categoriesJson) as List<dynamic>;
  final coRaw = jsonDecode(data.countriesJson) as List<dynamic>;
  final langRaw = jsonDecode(data.languagesJson) as List<dynamic>;

  // Parse into typed objects
  final channelsList = chRaw
      .map((c) => IPTVChannelRaw.fromJson(c as Map<String, dynamic>))
      .toList();
  final streamsList = stRaw
      .map((s) => IPTVStreamRaw.fromJson(s as Map<String, dynamic>))
      .toList();
  final logosList = lgRaw
      .map((l) => IPTVLogoRaw.fromJson(l as Map<String, dynamic>))
      .toList();
  final categoriesList = catRaw
      .map((c) => IPTVCategoryRaw.fromJson(c as Map<String, dynamic>))
      .toList();
  final countriesList = coRaw
      .map((c) => IPTVCountryRaw.fromJson(c as Map<String, dynamic>))
      .toList();
  final languagesList = langRaw
      .map((l) => IPTVLanguageRaw.fromJson(l as Map<String, dynamic>))
      .toList();

  // Build lookup maps
  final logoMap = <String, String>{};
  for (final logo in logosList) {
    if (!logoMap.containsKey(logo.channel) || logo.feed == null) {
      logoMap[logo.channel] = logo.url;
    }
  }

  final categoryMap = <String, String>{};
  for (final c in categoriesList) {
    categoryMap[c.id] = c.name;
  }

  final countryMap = <String, Map<String, dynamic>>{};
  for (final co in countriesList) {
    countryMap[co.code] = {
      'name': co.name,
      'flag': co.flag,
      'languages': List<String>.from(co.languages.map((e) => e.toString()))
    };
  }

  final languageMap = <String, String>{};
  for (final l in languagesList) {
    languageMap[l.code] = l.name;
  }

  final streamMap = <String, IPTVStreamRaw>{};
  for (final s in streamsList) {
    if (s.channel != null && s.url.isNotEmpty) {
      if (!streamMap.containsKey(s.channel!)) streamMap[s.channel!] = s;
    }
  }

  // Merge and create Channel objects
  final List<Channel> merged = [];
  for (final ch in channelsList) {
    if (ch.isNsfw || (ch.closed != null && ch.closed!.isNotEmpty)) continue;
    final s = streamMap[ch.id];
    if (s == null) continue;

    final countryInfo = countryMap[ch.country] ??
        {'name': ch.country, 'flag': '🌐', 'languages': <String>[]};
    final primaryCategory =
        (ch.categories.isNotEmpty ? ch.categories[0].toString() : 'general');
    final channelLangs =
        List<String>.from(countryInfo['languages'] as List<dynamic>);
    final channelLangNames =
        channelLangs.map((c) => languageMap[c] ?? c).toList();

    merged.add(Channel(
      id: ch.id,
      name: ch.name,
      country: ch.country,
      countryName: countryInfo['name'] as String,
      countryFlag: countryInfo['flag'] as String,
      category: primaryCategory,
      categoryName: categoryMap[primaryCategory] ?? primaryCategory,
      categories: ch.categories,
      logo: logoMap[ch.id] ?? '',
      url: s.url,
      quality: s.quality,
      languages: channelLangs,
      languageNames: channelLangNames,
      isNsfw: ch.isNsfw,
      network: ch.network,
      website: ch.website,
      referrer: s.referrer,
      userAgent: s.userAgent,
    ));
  }

  merged.sort((a, b) => a.name.compareTo(b.name));
  return merged;
}

class IptvService extends ChangeNotifier {
  List<Channel> _channels = [];
  bool _loading = false;
  String? _error;
  String _progress = 'Idle';

  List<Channel> get channels => _channels;
  bool get loading => _loading;
  String? get error => _error;
  String get progress => _progress;

  static const apiBase = 'https://iptv-org.github.io/api';
  static const endpoints = {
    'channels': '$apiBase/channels.json',
    'streams': '$apiBase/streams.json',
    'logos': '$apiBase/logos.json',
    'categories': '$apiBase/categories.json',
    'countries': '$apiBase/countries.json',
    'languages': '$apiBase/languages.json',
  };

  static const cacheDurationMs = 1000 * 60 * 60; // 1 hour

  Future<Directory> _cacheDir() async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/iptv_cache');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    return cacheDir;
  }

  Future<File> _cacheFile(String name) async {
    final dir = await _cacheDir();
    return File('${dir.path}/$name.json');
  }

  Future<bool> _isCacheValid(File file) async {
    if (!await file.exists()) return false;
    final stat = await file.stat();
    final age = DateTime.now().difference(stat.modified).inMilliseconds;
    return age <= cacheDurationMs;
  }

  Future<void> loadChannels({bool forceRefresh = false}) async {
    _loading = true;
    _error = null;
    _progress = 'Checking cache...';
    notifyListeners();

    try {
      // Check local cache
      final channelFile = await _cacheFile('channels');
      final streamsFile = await _cacheFile('streams');
      final logosFile = await _cacheFile('logos');
      final categoriesFile = await _cacheFile('categories');
      final countriesFile = await _cacheFile('countries');
      final languagesFile = await _cacheFile('languages');

      bool useCache = !forceRefresh &&
          await _isCacheValid(channelFile) &&
          await _isCacheValid(streamsFile);

      if (useCache) {
        _progress = 'Loading from cache...';
        notifyListeners();
        // cached files exist; we'll read them below
      } else {
        _progress = 'Fetching channels...';
        notifyListeners();
        final chRes = await http.get(Uri.parse(endpoints['channels']!));
        if (chRes.statusCode != 200)
          throw Exception('Failed to fetch channels');
        final channelsData = jsonDecode(chRes.body) as List<dynamic>;
        await channelFile.writeAsString(jsonEncode(channelsData));

        _progress = 'Fetching streams...';
        notifyListeners();
        final stRes = await http.get(Uri.parse(endpoints['streams']!));
        if (stRes.statusCode != 200) throw Exception('Failed to fetch streams');
        final streamsData = jsonDecode(stRes.body) as List<dynamic>;
        await streamsFile.writeAsString(jsonEncode(streamsData));

        _progress = 'Fetching logos...';
        notifyListeners();
        final lgRes = await http.get(Uri.parse(endpoints['logos']!));
        if (lgRes.statusCode != 200) throw Exception('Failed to fetch logos');
        final logosData = jsonDecode(lgRes.body) as List<dynamic>;
        await logosFile.writeAsString(jsonEncode(logosData));

        _progress = 'Fetching categories...';
        notifyListeners();
        final catRes = await http.get(Uri.parse(endpoints['categories']!));
        if (catRes.statusCode != 200)
          throw Exception('Failed to fetch categories');
        final categoriesData = jsonDecode(catRes.body) as List<dynamic>;
        await categoriesFile.writeAsString(jsonEncode(categoriesData));

        _progress = 'Fetching countries...';
        notifyListeners();
        final coRes = await http.get(Uri.parse(endpoints['countries']!));
        if (coRes.statusCode != 200)
          throw Exception('Failed to fetch countries');
        final countriesData = jsonDecode(coRes.body) as List<dynamic>;
        await countriesFile.writeAsString(jsonEncode(countriesData));

        _progress = 'Fetching languages...';
        notifyListeners();
        final lgRes2 = await http.get(Uri.parse(endpoints['languages']!));
        if (lgRes2.statusCode != 200)
          throw Exception('Failed to fetch languages');
        final languagesData = jsonDecode(lgRes2.body) as List<dynamic>;
        await languagesFile.writeAsString(jsonEncode(languagesData));

        // data cached to files; will read from files below for merging
      }

      _progress = 'Processing data (background)...';
      notifyListeners();

      // Read raw JSON strings - these will be passed to isolate
      final channelsJson = await channelFile.readAsString();
      final streamsJson = await streamsFile.readAsString();
      final logosJson = await logosFile.readAsString();
      final categoriesJson = await categoriesFile.readAsString();
      final countriesJson = await countriesFile.readAsString();
      final languagesJson = await languagesFile.readAsString();

      // CRITICAL: Use compute isolate to prevent UI blocking
      // Processing 8000+ channels on main thread causes "Not Responding"
      final processingData = _ProcessingData(
        channelsJson: channelsJson,
        streamsJson: streamsJson,
        logosJson: logosJson,
        categoriesJson: categoriesJson,
        countriesJson: countriesJson,
        languagesJson: languagesJson,
      );

      final merged = await compute(_processChannelsInIsolate, processingData);

      _channels = merged;
      _progress = 'Loaded ${_channels.length} channels';
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // Helpers to get unique filters
  List<Map<String, String>> getUniqueCategories() {
    final map = <String, String>{};
    for (final ch in _channels) {
      if (!map.containsKey(ch.category)) map[ch.category] = ch.categoryName;
    }
    final list = map.entries.map((e) => {'id': e.key, 'name': e.value}).toList()
      ..sort((a, b) => a['name']!.compareTo(b['name']!));
    return list;
  }

  List<Map<String, String>> getUniqueCountries() {
    final map = <String, String>{};
    for (final ch in _channels) {
      if (!map.containsKey(ch.country)) map[ch.country] = ch.countryName;
    }
    final list = map.entries
        .map((e) => {'code': e.key, 'name': e.value})
        .toList()
      ..sort((a, b) => a['name']!.compareTo(b['name']!));
    return list;
  }

  List<Map<String, String>> getUniqueLanguages() {
    final map = <String, String>{};
    for (final ch in _channels) {
      for (var i = 0; i < ch.languages.length; i++) {
        final code = ch.languages[i];
        final name = (i < ch.languageNames.length) ? ch.languageNames[i] : code;
        if (!map.containsKey(code)) map[code] = name;
      }
    }
    final list = map.entries
        .map((e) => {'code': e.key, 'name': e.value})
        .toList()
      ..sort((a, b) => a['name']!.compareTo(b['name']!));
    return list;
  }
}
