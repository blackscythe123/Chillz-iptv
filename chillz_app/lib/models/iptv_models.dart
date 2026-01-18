// Minimal models for iptv-org data and merged channel

class IPTVChannelRaw {
  final String id;
  final String name;
  final List<dynamic> altNames;
  final String? network;
  final List<dynamic> owners;
  final String country;
  final List<dynamic> categories;
  final bool isNsfw;
  final String? launched;
  final String? closed;
  final String? website;

  IPTVChannelRaw.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        altNames = (json['alt_names'] ?? []) as List<dynamic>,
        network = json['network'] as String?,
        owners = (json['owners'] ?? []) as List<dynamic>,
        country = json['country'] as String? ?? '',
        categories = (json['categories'] ?? []) as List<dynamic>,
        isNsfw = json['is_nsfw'] as bool? ?? false,
        launched = json['launched'] as String?,
        closed = json['closed'] as String?,
        website = json['website'] as String?;
}

class IPTVStreamRaw {
  final String? channel;
  final String? feed;
  final String title;
  final String url;
  final String? referrer;
  final String? userAgent;
  final String? quality;

  IPTVStreamRaw.fromJson(Map<String, dynamic> json)
      : channel = json['channel'] as String?,
        feed = json['feed'] as String?,
        title = json['title'] as String? ?? '',
        url = json['url'] as String? ?? '',
        referrer = json['referrer'] as String?,
        userAgent = json['user_agent'] as String?,
        quality = json['quality'] as String?;
}

class IPTVLogoRaw {
  final String channel;
  final String? feed;
  final String url;

  IPTVLogoRaw.fromJson(Map<String, dynamic> json)
      : channel = json['channel'] as String,
        feed = json['feed'] as String?,
        url = json['url'] as String? ?? '';
}

class IPTVCategoryRaw {
  final String id;
  final String name;
  IPTVCategoryRaw.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String;
}

class IPTVCountryRaw {
  final String name;
  final String code;
  final List<dynamic> languages;
  final String flag;
  IPTVCountryRaw.fromJson(Map<String, dynamic> json)
      : name = json['name'] as String,
        code = json['code'] as String,
        languages = (json['languages'] ?? []) as List<dynamic>,
        flag = json['flag'] as String? ?? '';
}

class IPTVLanguageRaw {
  final String name;
  final String code;
  IPTVLanguageRaw.fromJson(Map<String, dynamic> json)
      : name = json['name'] as String,
        code = json['code'] as String;
}

class Channel {
  final String id;
  final String name;
  final String country;
  final String countryName;
  final String countryFlag;
  final String category;
  final String categoryName;
  final List<dynamic> categories;
  final String logo;
  final String url;
  final String? quality;
  final List<String> languages;
  final List<String> languageNames;
  final bool isNsfw;
  final String? network;
  final String? website;
  final String? referrer;
  final String? userAgent;

  Channel({
    required this.id,
    required this.name,
    required this.country,
    required this.countryName,
    required this.countryFlag,
    required this.category,
    required this.categoryName,
    required this.categories,
    required this.logo,
    required this.url,
    required this.quality,
    required this.languages,
    required this.languageNames,
    required this.isNsfw,
    this.network,
    this.website,
    this.referrer,
    this.userAgent,
  });
}
