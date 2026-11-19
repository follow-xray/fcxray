import '../models/profile.dart';
import '../models/resources.dart';
import '../models/route_override.dart';

enum ConnectionMode { vpn, proxy }

enum RoutingMode {
  direct('直连'),
  rules('规则'),
  global('全局');

  const RoutingMode(this.label);
  final String label;
}

class ConfigBuilder {
  static Map<String, dynamic> build(
    Profile? profile, {
    required String platform,
    ConnectionMode mode = ConnectionMode.vpn,
    RoutingMode routing = RoutingMode.rules,
    bool bypassLan = true,
    bool useGeo = false,
    List<RouteOverride> overrides = const [],
    Map<String, GeoAsset> geoAssets = const {},
    GeoRouting geoRouting = const GeoRouting(),
  }) {
    if (routing != RoutingMode.direct && profile == null) {
      throw const FormatException('规则和全局模式需要先选择节点');
    }
    final geoEnabled = routing == RoutingMode.rules && useGeo;
    final custom = routing == RoutingMode.rules
        ? overrides.where((r) => r.enabled).toList()
        : <RouteOverride>[];
    // Router reload replaces rules, but cannot change inbound sniffing or DNS strategy.
    final sniff = routing == RoutingMode.rules;
    final android = platform == 'android';
    final tun = mode == ConnectionMode.vpn;
    List<String> geo(String kind, List<String> tags) {
      if (tags.isEmpty) return [];
      final asset = geoAssets[kind];
      if (asset == null || !asset.installed) {
        throw FormatException('请先导入或下载 $kind 规则库');
      }
      for (final tag in tags) {
        if (!asset.tags.contains(tag.split('@').first.toLowerCase())) {
          throw FormatException('$kind 不包含分类 $tag');
        }
      }
      return tags.map((tag) => 'ext:${asset.fileName}:$tag').toList();
    }

    final geoRules = <Map<String, dynamic>>[];
    if (geoEnabled) {
      final blocked = geo('geosite', geoRouting.blockSites);
      final directSites = geo('geosite', geoRouting.directSites);
      final directIPs = geo('geoip', geoRouting.directIPs);
      if (blocked.isNotEmpty) {
        geoRules.add({
          'type': 'field',
          'domain': blocked,
          'outboundTag': 'block',
        });
      }
      if (directSites.isNotEmpty) {
        geoRules.add({
          'type': 'field',
          'domain': directSites,
          'outboundTag': 'direct',
        });
      }
      if (directIPs.isNotEmpty) {
        geoRules.add({
          'type': 'field',
          'ip': directIPs,
          'outboundTag': 'direct',
        });
      }
    }
    return {
      'log': {'loglevel': 'warning', 'access': 'none', 'dnsLog': false},
      'stats': <String, dynamic>{},
      'policy': {
        'system': {
          'statsOutboundUplink': true,
          'statsInboundUplink': true,
          'statsInboundDownlink': true,
          'statsOutboundDownlink': true,
        },
      },
      'dns': {
        'servers': ['https://1.1.1.1/dns-query'],
        'queryStrategy': 'UseIP',
      },
      'inbounds': [
        if (tun)
          {
            'tag': 'tun-in',
            'protocol': 'tun',
            if (sniff)
              'sniffing': {
                'enabled': true,
                'destOverride': ['http', 'tls', 'quic'],
                'routeOnly': true,
              },
            'settings': {
              'mtu': 1500,
              // Android supplies an open TUN fd. A logical name avoids Xray's
              // desktop interface-name discovery, which needs restricted netlink.
              if (android) 'name': 'fcxray',
              if (!android) ...{
                'gateway': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
                'autoSystemRoutingTable': ['0.0.0.0/0', '::/0'],
                'autoOutboundsInterface': 'auto',
                if (platform == 'windows') ...{
                  'name': 'fcxray',
                  'dns': ['1.1.1.1'],
                  'autoSystemWfpBlockLeak': ['dns', 'misconfigtun'],
                },
              },
            },
          },
        {
          'tag': 'socks-in',
          'listen': '127.0.0.1',
          'port': 10808,
          'protocol': 'socks',
          if (sniff)
            'sniffing': {
              'enabled': true,
              'destOverride': ['http', 'tls', 'quic'],
              'routeOnly': true,
            },
          'settings': {'auth': 'noauth', 'udp': true},
        },
        {
          'tag': 'http-in',
          'listen': '127.0.0.1',
          'port': 10809,
          'protocol': 'http',
          'settings': <String, dynamic>{},
        },
      ],
      'outbounds': [
        if (routing != RoutingMode.direct)
          {...profile!.outbound, 'tag': 'proxy'},
        {
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': <String, dynamic>{},
        },
        {
          'tag': 'block',
          'protocol': 'blackhole',
          'settings': <String, dynamic>{},
        },
        {'tag': 'dns-out', 'protocol': 'dns', 'settings': <String, dynamic>{}},
      ],
      'routing': {
        'domainStrategy': routing == RoutingMode.rules
            ? 'IPIfNonMatch'
            : 'AsIs',
        'rules': [
          if (routing != RoutingMode.direct && profile!.protocol == 'loopback')
            {
              'type': 'field',
              'inboundTag': [
                (profile.outbound['settings'] as Map)['inboundTag'],
              ],
              'outboundTag': 'direct',
            },
          // Must precede LAN bypass: local resolvers captured by TUN go through DoH.
          if (tun)
            {
              'type': 'field',
              'inboundTag': ['tun-in'],
              'port': '53',
              'outboundTag': 'dns-out',
            },
          for (final rule in custom) rule.toXray(),
          if (routing == RoutingMode.rules && bypassLan)
            {
              'type': 'field',
              'ip': [
                '10.0.0.0/8',
                '172.16.0.0/12',
                '192.168.0.0/16',
                '127.0.0.0/8',
                '169.254.0.0/16',
                '::1/128',
                'fc00::/7',
                'fe80::/10',
              ],
              'outboundTag': 'direct',
            },
          ...geoRules,
        ],
      },
    };
  }
}
