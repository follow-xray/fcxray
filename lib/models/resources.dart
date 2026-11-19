import 'profile.dart';

enum SubscriptionAgent {
  xray('Xray（v2rayN）'),
  clash('Clash（FlClash）'),
  custom('自定义');

  const SubscriptionAgent(this.label);
  final String label;
  static const xrayHeader = 'v2rayN/7.25.6';
  String header(String platform, String customValue) => switch (this) {
    xray => xrayHeader,
    clash => 'FlClash/v0.8.96 clash-verge Platform/$platform',
    custom => customValue,
  };

  static bool validCustom(String value) =>
      value.trim().isNotEmpty && !RegExp(r'[^ -~]').hasMatch(value);
}

/// Optional byte counts and Unix expiry reported by the subscription provider.
class SubscriptionUsage {
  const SubscriptionUsage(this.upload, this.download, this.total, this.expire);
  final int? upload, download, total, expire;

  static SubscriptionUsage? fromFields(Map fields) {
    int? number(String key) {
      final raw = fields[key];
      final n = raw is int
          ? raw
          : int.tryParse(raw?.toString() ?? '', radix: 10);
      return n != null && n >= 0 ? n : null;
    }

    final up = number('upload'),
        down = number('download'),
        advertisedTotal = number('total');
    final total = advertisedTotal == 0 ? null : advertisedTotal;
    final seconds = number('expire');
    // Zero means no advertised expiry. Bound conversion to a displayable year.
    final expiry = seconds != null && seconds > 0 && seconds <= 253402300799
        ? seconds
        : null;
    return up == null && down == null && total == null && expiry == null
        ? null
        : SubscriptionUsage(up, down, total, expiry);
  }

  static SubscriptionUsage? parse(String? header) {
    if (header == null) return null;
    final fields = <String, String>{};
    for (final pair in header.split(RegExp('[;,]'))) {
      final split = pair.indexOf('=');
      if (split > 0) {
        fields[pair.substring(0, split).trim().toLowerCase()] = pair
            .substring(split + 1)
            .trim();
      }
    }
    return fromFields(fields);
  }

  Map<String, dynamic> toJson() => {
    'upload': upload,
    'download': download,
    'total': total,
    'expire': expire,
  };
}

class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.url,
    this.autoHours = 0,
    this.updatedAt,
    this.attemptedAt,
    this.error,
    this.usage,
  });
  final String id, name, url;
  final int autoHours;
  final DateTime? updatedAt, attemptedAt;
  final String? error;
  final SubscriptionUsage? usage;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'autoHours': autoHours,
    'updatedAt': updatedAt?.toIso8601String(),
    'attemptedAt': attemptedAt?.toIso8601String(),
    'error': error,
    if (usage != null) 'usage': usage!.toJson(),
  };
  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
    id: j['id'] as String,
    name: j['name'] as String,
    url: j['url'] as String,
    autoHours: j['autoHours'] as int? ?? 0,
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
    attemptedAt: DateTime.tryParse(j['attemptedAt'] as String? ?? ''),
    error: j['error'] as String?,
    usage: j['usage'] is Map
        ? SubscriptionUsage.fromFields(j['usage'] as Map)
        : null,
  );
  Subscription result({
    required DateTime now,
    String? failure,
    SubscriptionUsage? usage,
  }) => Subscription(
    id: id,
    name: name,
    url: url,
    autoHours: autoHours,
    updatedAt: failure == null ? now : updatedAt,
    attemptedAt: now,
    error: failure,
    usage: failure == null ? usage : this.usage,
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
    tags: (j['tags'] as List? ?? []).cast<String>().toList(),
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
    directIPs: (j['directIPs'] as List? ?? ['cn']).cast<String>().toList(),
    directSites: (j['directSites'] as List? ?? ['cn']).cast<String>().toList(),
    blockSites: (j['blockSites'] as List? ?? []).cast<String>().toList(),
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
