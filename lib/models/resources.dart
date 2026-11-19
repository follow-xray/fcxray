import 'profile.dart';

class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.url,
    this.autoHours = 0,
    this.updatedAt,
    this.attemptedAt,
    this.error,
  });
  final String id, name, url;
  final int autoHours;
  final DateTime? updatedAt, attemptedAt;
  final String? error;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'autoHours': autoHours,
    'updatedAt': updatedAt?.toIso8601String(),
    'attemptedAt': attemptedAt?.toIso8601String(),
    'error': error,
  };
  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
    id: j['id'] as String,
    name: j['name'] as String,
    url: j['url'] as String,
    autoHours: j['autoHours'] as int? ?? 0,
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
    attemptedAt: DateTime.tryParse(j['attemptedAt'] as String? ?? ''),
    error: j['error'] as String?,
  );
  Subscription result({required DateTime now, String? failure}) => Subscription(
    id: id,
    name: name,
    url: url,
    autoHours: autoHours,
    updatedAt: failure == null ? now : updatedAt,
    attemptedAt: now,
    error: failure,
  );
  factory Subscription.create(String name, String url, int hours) =>
      Subscription(id: Profile.newId(), name: name, url: url, autoHours: hours);
}

class GeoAsset {
  const GeoAsset({
    required this.kind,
    required this.url,
    this.autoHours = 0,
    this.expectedHash = '',
    this.fileName,
    this.hash = '',
    this.size = 0,
    this.entries = 0,
    this.tags = const [],
    this.updatedAt,
    this.attemptedAt,
    this.error,
  });
  final String kind, url, expectedHash, hash;
  final int autoHours, size, entries;
  final String? fileName, error;
  final List<String> tags;
  final DateTime? updatedAt, attemptedAt;
  bool get installed => fileName != null;
  factory GeoAsset.defaults(String kind) => GeoAsset(
    kind: kind,
    url:
        'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/$kind.dat',
  );
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'url': url,
    'autoHours': autoHours,
    'expectedHash': expectedHash,
    'fileName': fileName,
    'hash': hash,
    'size': size,
    'entries': entries,
    'tags': tags,
    'updatedAt': updatedAt?.toIso8601String(),
    'attemptedAt': attemptedAt?.toIso8601String(),
    'error': error,
  };
  factory GeoAsset.fromJson(Map<String, dynamic> j) => GeoAsset(
    kind: j['kind'] as String,
    url: j['url'] as String,
    autoHours: j['autoHours'] as int? ?? 0,
    expectedHash: j['expectedHash'] as String? ?? '',
    fileName: j['fileName'] as String?,
    hash: j['hash'] as String? ?? '',
    size: j['size'] as int? ?? 0,
    entries: j['entries'] as int? ?? 0,
    tags: (j['tags'] as List? ?? []).cast<String>(),
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
    attemptedAt: DateTime.tryParse(j['attemptedAt'] as String? ?? ''),
    error: j['error'] as String?,
  );
  GeoAsset withSettings(String source, String expected, int hours) =>
      GeoAsset.fromJson({
        ...toJson(),
        'url': source,
        'expectedHash': expected,
        'autoHours': hours,
      });
  GeoAsset failure(String message) => GeoAsset.fromJson({
    ...toJson(),
    'error': message,
    'attemptedAt': DateTime.now().toIso8601String(),
  });
}

class GeoRouting {
  const GeoRouting({
    this.directIPs = const ['cn'],
    this.directSites = const ['cn'],
    this.blockSites = const [],
  });
  final List<String> directIPs, directSites, blockSites;
  Map<String, dynamic> toJson() => {
    'directIPs': directIPs,
    'directSites': directSites,
    'blockSites': blockSites,
  };
  factory GeoRouting.fromJson(Map<String, dynamic> j) => GeoRouting(
    directIPs: (j['directIPs'] as List? ?? ['cn']).cast<String>(),
    directSites: (j['directSites'] as List? ?? ['cn']).cast<String>(),
    blockSites: (j['blockSites'] as List? ?? []).cast<String>(),
  );
  static List<String> parseTags(String value) {
    final tags = value
        .split(RegExp(r'[,，\s]+'))
        .where((s) => s.isNotEmpty)
        .map((s) => s.toLowerCase())
        .toSet()
        .toList();
    if (tags.length > 64 ||
        tags.any(
          (s) => !RegExp(r'^[a-z0-9_!.-]+(?:@[a-z0-9_-]+)?$').hasMatch(s),
        )) {
      throw const FormatException('分类名称无效，最多 64 项，请使用逗号分隔');
    }
    return tags;
  }
}
