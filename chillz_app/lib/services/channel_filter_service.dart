// Channel Filter Service - Efficient filtering and sorting for IPTV channels
// Optimized for large channel lists (8000+ channels) with O(n) operations

import 'package:flutter/foundation.dart';
import '../models/iptv_models.dart';

/// Sort options for channel list
enum ChannelSortOption {
  name,
  country,
  category,
  language,
}

/// Sort direction
enum SortDirection {
  ascending,
  descending,
}

/// Filter state for channels
class ChannelFilter {
  final String? country;
  final String? category;
  final String? language;
  final String? searchQuery;

  const ChannelFilter({
    this.country,
    this.category,
    this.language,
    this.searchQuery,
  });

  bool get hasFilters =>
      country != null ||
      category != null ||
      language != null ||
      (searchQuery != null && searchQuery!.isNotEmpty);

  ChannelFilter copyWith({
    String? country,
    String? category,
    String? language,
    String? searchQuery,
    bool clearCountry = false,
    bool clearCategory = false,
    bool clearLanguage = false,
    bool clearSearch = false,
  }) {
    return ChannelFilter(
      country: clearCountry ? null : (country ?? this.country),
      category: clearCategory ? null : (category ?? this.category),
      language: clearLanguage ? null : (language ?? this.language),
      searchQuery: clearSearch ? null : (searchQuery ?? this.searchQuery),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelFilter &&
          country == other.country &&
          category == other.category &&
          language == other.language &&
          searchQuery == other.searchQuery;

  @override
  int get hashCode =>
      country.hashCode ^
      category.hashCode ^
      language.hashCode ^
      searchQuery.hashCode;
}

/// Channel Filter Service
/// Provides efficient filtering and sorting for large channel lists
class ChannelFilterService extends ChangeNotifier {
  // Source data
  List<Channel> _allChannels = [];

  // Filter state
  ChannelFilter _currentFilter = const ChannelFilter();
  ChannelSortOption _sortOption = ChannelSortOption.name;
  SortDirection _sortDirection = SortDirection.ascending;

  // Cached results
  List<Channel> _filteredChannels = [];
  bool _isDirty = true;

  // Cached unique values (computed once)
  List<String>? _uniqueCountries;
  List<String>? _uniqueCategories;
  List<String>? _uniqueLanguages;

  // Index maps for O(1) lookups
  Map<String, List<int>>? _countryIndex;
  Map<String, List<int>>? _categoryIndex;
  Map<String, List<int>>? _languageIndex;

  // Getters
  ChannelFilter get currentFilter => _currentFilter;
  ChannelSortOption get sortOption => _sortOption;
  SortDirection get sortDirection => _sortDirection;
  int get totalChannels => _allChannels.length;

  /// Get filtered and sorted channels
  List<Channel> get channels {
    if (_isDirty) {
      _applyFiltersAndSort();
    }
    return _filteredChannels;
  }

  /// Get unique countries from all channels
  List<String> get uniqueCountries {
    _uniqueCountries ??= _computeUniqueValues((c) => c.countryName);
    return _uniqueCountries!;
  }

  /// Get unique categories from all channels
  List<String> get uniqueCategories {
    _uniqueCategories ??= _computeUniqueValues((c) => c.categoryName);
    return _uniqueCategories!;
  }

  /// Get unique languages from all channels
  List<String> get uniqueLanguages {
    if (_uniqueLanguages != null) return _uniqueLanguages!;

    final Set<String> langs = {};
    for (final channel in _allChannels) {
      langs.addAll(channel.languageNames);
    }
    final sorted = langs.toList()..sort();
    _uniqueLanguages = sorted;
    return sorted;
  }

  /// Set the source channel list
  /// This builds indices for fast filtering
  void setChannels(List<Channel> channels) {
    _allChannels = channels;
    _invalidateCache();
    _buildIndices();
    notifyListeners();
  }

  /// Update filter criteria
  void setFilter(ChannelFilter filter) {
    if (_currentFilter != filter) {
      _currentFilter = filter;
      _isDirty = true;
      notifyListeners();
    }
  }

  /// Update sort option
  void setSortOption(ChannelSortOption option) {
    if (_sortOption != option) {
      _sortOption = option;
      _isDirty = true;
      notifyListeners();
    }
  }

  /// Update sort direction
  void setSortDirection(SortDirection direction) {
    if (_sortDirection != direction) {
      _sortDirection = direction;
      _isDirty = true;
      notifyListeners();
    }
  }

  /// Toggle sort direction
  void toggleSortDirection() {
    _sortDirection = _sortDirection == SortDirection.ascending
        ? SortDirection.descending
        : SortDirection.ascending;
    _isDirty = true;
    notifyListeners();
  }

  /// Set search query
  void setSearchQuery(String? query) {
    final normalizedQuery =
        query?.trim().isEmpty == true ? null : query?.trim();
    if (_currentFilter.searchQuery != normalizedQuery) {
      _currentFilter = _currentFilter.copyWith(
        searchQuery: normalizedQuery,
        clearSearch: normalizedQuery == null,
      );
      _isDirty = true;
      notifyListeners();
    }
  }

  /// Set country filter
  void setCountryFilter(String? country) {
    _currentFilter = _currentFilter.copyWith(
      country: country,
      clearCountry: country == null,
    );
    _isDirty = true;
    notifyListeners();
  }

  /// Set category filter
  void setCategoryFilter(String? category) {
    _currentFilter = _currentFilter.copyWith(
      category: category,
      clearCategory: category == null,
    );
    _isDirty = true;
    notifyListeners();
  }

  /// Set language filter
  void setLanguageFilter(String? language) {
    _currentFilter = _currentFilter.copyWith(
      language: language,
      clearLanguage: language == null,
    );
    _isDirty = true;
    notifyListeners();
  }

  /// Clear all filters
  void clearFilters() {
    _currentFilter = const ChannelFilter();
    _isDirty = true;
    notifyListeners();
  }

  /// Reset to default state
  void reset() {
    _currentFilter = const ChannelFilter();
    _sortOption = ChannelSortOption.name;
    _sortDirection = SortDirection.ascending;
    _isDirty = true;
    notifyListeners();
  }

  // ============== Private Methods ==============

  void _invalidateCache() {
    _isDirty = true;
    _uniqueCountries = null;
    _uniqueCategories = null;
    _uniqueLanguages = null;
    _countryIndex = null;
    _categoryIndex = null;
    _languageIndex = null;
  }

  /// Build index maps for O(1) filter lookups
  void _buildIndices() {
    _countryIndex = {};
    _categoryIndex = {};
    _languageIndex = {};

    for (int i = 0; i < _allChannels.length; i++) {
      final channel = _allChannels[i];

      // Country index
      final countryKey = channel.countryName.toLowerCase();
      _countryIndex!.putIfAbsent(countryKey, () => []).add(i);

      // Category index
      final categoryKey = channel.categoryName.toLowerCase();
      _categoryIndex!.putIfAbsent(categoryKey, () => []).add(i);

      // Language index (multiple languages per channel)
      for (final lang in channel.languageNames) {
        final langKey = lang.toLowerCase();
        _languageIndex!.putIfAbsent(langKey, () => []).add(i);
      }
    }
  }

  List<String> _computeUniqueValues(String Function(Channel) extractor) {
    final Set<String> values = {};
    for (final channel in _allChannels) {
      final value = extractor(channel);
      if (value.isNotEmpty) {
        values.add(value);
      }
    }
    final sorted = values.toList()..sort();
    return sorted;
  }

  /// Apply current filters and sort - O(n) operation
  void _applyFiltersAndSort() {
    if (_allChannels.isEmpty) {
      _filteredChannels = [];
      _isDirty = false;
      return;
    }

    // Start with all channels or use index for single filter
    Set<int>? candidateIndices;

    // Use indices for faster filtering when possible
    if (_currentFilter.country != null && _countryIndex != null) {
      final key = _currentFilter.country!.toLowerCase();
      final indices = _countryIndex![key];
      candidateIndices = indices?.toSet();
    }

    if (_currentFilter.category != null && _categoryIndex != null) {
      final key = _currentFilter.category!.toLowerCase();
      final indices = _categoryIndex![key]?.toSet();
      if (indices != null) {
        candidateIndices = candidateIndices?.intersection(indices) ?? indices;
      }
    }

    if (_currentFilter.language != null && _languageIndex != null) {
      final key = _currentFilter.language!.toLowerCase();
      final indices = _languageIndex![key]?.toSet();
      if (indices != null) {
        candidateIndices = candidateIndices?.intersection(indices) ?? indices;
      }
    }

    // Get candidate channels
    List<Channel> candidates;
    if (candidateIndices != null) {
      candidates = candidateIndices.map((i) => _allChannels[i]).toList();
    } else {
      candidates = List.from(_allChannels);
    }

    // Apply search filter (always linear)
    final searchQuery = _currentFilter.searchQuery?.toLowerCase();
    if (searchQuery != null && searchQuery.isNotEmpty) {
      candidates = candidates.where((channel) {
        return channel.name.toLowerCase().contains(searchQuery) ||
            channel.countryName.toLowerCase().contains(searchQuery) ||
            channel.categoryName.toLowerCase().contains(searchQuery);
      }).toList();
    }

    // Sort
    _sortChannels(candidates);

    _filteredChannels = candidates;
    _isDirty = false;
  }

  void _sortChannels(List<Channel> channels) {
    final ascending = _sortDirection == SortDirection.ascending;

    channels.sort((a, b) {
      int result;

      switch (_sortOption) {
        case ChannelSortOption.name:
          result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case ChannelSortOption.country:
          result = a.countryName
              .toLowerCase()
              .compareTo(b.countryName.toLowerCase());
          // Secondary sort by name
          if (result == 0) {
            result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          break;
        case ChannelSortOption.category:
          result = a.categoryName
              .toLowerCase()
              .compareTo(b.categoryName.toLowerCase());
          // Secondary sort by name
          if (result == 0) {
            result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          break;
        case ChannelSortOption.language:
          final langA = a.languageNames.isNotEmpty ? a.languageNames.first : '';
          final langB = b.languageNames.isNotEmpty ? b.languageNames.first : '';
          result = langA.toLowerCase().compareTo(langB.toLowerCase());
          // Secondary sort by name
          if (result == 0) {
            result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          break;
      }

      return ascending ? result : -result;
    });
  }

  /// Get filtered count for a specific country
  int getChannelCountByCountry(String country) {
    final key = country.toLowerCase();
    return _countryIndex?[key]?.length ?? 0;
  }

  /// Get filtered count for a specific category
  int getChannelCountByCategory(String category) {
    final key = category.toLowerCase();
    return _categoryIndex?[key]?.length ?? 0;
  }

  /// Get filtered count for a specific language
  int getChannelCountByLanguage(String language) {
    final key = language.toLowerCase();
    return _languageIndex?[key]?.length ?? 0;
  }

  /// Find channel index by ID
  int findChannelIndex(String channelId) {
    return channels.indexWhere((c) => c.id == channelId);
  }

  /// Get channel at index in filtered list
  Channel? getChannelAt(int index) {
    if (index >= 0 && index < channels.length) {
      return channels[index];
    }
    return null;
  }

  /// Get next channel (for channel up)
  Channel? getNextChannel(String currentId) {
    final currentIndex = findChannelIndex(currentId);
    if (currentIndex >= 0 && currentIndex < channels.length - 1) {
      return channels[currentIndex + 1];
    } else if (channels.isNotEmpty) {
      return channels.first; // Wrap around
    }
    return null;
  }

  /// Get previous channel (for channel down)
  Channel? getPreviousChannel(String currentId) {
    final currentIndex = findChannelIndex(currentId);
    if (currentIndex > 0) {
      return channels[currentIndex - 1];
    } else if (channels.isNotEmpty) {
      return channels.last; // Wrap around
    }
    return null;
  }

  /// Get channel by number (1-indexed for remote input)
  Channel? getChannelByNumber(int number) {
    // Number is 1-indexed
    final index = number - 1;
    return getChannelAt(index);
  }
}
