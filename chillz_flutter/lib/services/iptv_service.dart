import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/iptv_models.dart';

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

      _progress = 'Processing data...';
      notifyListeners();

      // Parse lists
      List<IPTVChannelRaw> channelsList = [];
      List<IPTVStreamRaw> streamsList = [];
      List<IPTVLogoRaw> logosList = [];
      List<IPTVCategoryRaw> categoriesList = [];
      List<IPTVCountryRaw> countriesList = [];
      List<IPTVLanguageRaw> languagesList = [];

      // Depending on whether we used cache we might have individual lists or map container
      dynamic chRaw = jsonDecode(await channelFile.readAsString());
      dynamic stRaw = jsonDecode(await streamsFile.readAsString());
      dynamic lgRaw = jsonDecode(await logosFile.readAsString());
      dynamic catRaw = jsonDecode(await categoriesFile.readAsString());
      dynamic coRaw = jsonDecode(await countriesFile.readAsString());
      dynamic langRaw = jsonDecode(await languagesFile.readAsString());

      for (final c in chRaw as List<dynamic>) {
        channelsList.add(IPTVChannelRaw.fromJson(c as Map<String, dynamic>));
      }
      for (final s in stRaw as List<dynamic>) {
        streamsList.add(IPTVStreamRaw.fromJson(s as Map<String, dynamic>));
      }
      for (final l in lgRaw as List<dynamic>) {
        logosList.add(IPTVLogoRaw.fromJson(l as Map<String, dynamic>));
      }
      for (final c in catRaw as List<dynamic>) {
        categoriesList.add(IPTVCategoryRaw.fromJson(c as Map<String, dynamic>));
      }
      for (final c in coRaw as List<dynamic>) {
        countriesList.add(IPTVCountryRaw.fromJson(c as Map<String, dynamic>));
      }
      for (final l in langRaw as List<dynamic>) {
        languagesList.add(IPTVLanguageRaw.fromJson(l as Map<String, dynamic>));
      }

      // Merging logic (same as React implementation)
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

      final List<Channel> merged = [];
      for (final ch in channelsList) {
        if (ch.isNsfw || (ch.closed != null && ch.closed!.isNotEmpty)) continue;
        final s = streamMap[ch.id];
        if (s == null) continue;
        final countryInfo = countryMap[ch.country] ??
            {'name': ch.country, 'flag': '🌐', 'languages': <String>[]};
        final primaryCategory = (ch.categories.isNotEmpty
            ? ch.categories[0].toString()
            : 'general');
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
