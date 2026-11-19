import 'dart:convert';
import '../models/profile.dart';
import 'protocol_catalog.dart';

/// Imports outbound descriptions only. Routing and listeners remain app-managed.
class ProfileImporter {
  static String _decode(String s) =>
      utf8.decode(base64.decode(base64.normalize(s)));

  static List<Profile> parse(String input) {
    var text = input.trim();
    if (text.isEmpty) throw const FormatException('请粘贴节点链接或 Xray JSON');
    if (utf8.encode(text).length > 1024 * 1024) {
      throw const FormatException('配置不能超过 1 MiB');
    }
    if (text.startsWith('{') || text.startsWith('[')) {
      final decoded = jsonDecode(text);
      var entries = decoded is List
          ? decoded
          : (decoded['outbounds'] is List
                ? decoded['outbounds'] as List
                : [decoded]);
      // Utility outbounds in a full core config are dependencies, not extra
      // remote servers. Standalone utility objects remain importable.
      if (decoded is Map &&
          decoded['outbounds'] is List &&
          entries.any(
            (e) =>
                e is Map &&
                !ProtocolCatalog.utility.contains(
                  ProtocolCatalog.canonical('${e['protocol']}'),
                ),
          )) {
        entries = entries
            .where(
              (e) =>
                  e is! Map ||
                  !ProtocolCatalog.utility.contains(
                    ProtocolCatalog.canonical('${e['protocol']}'),
                  ),
            )
            .toList();
      }
      final profiles = <Profile>[];
      for (final entry in entries) {
        if (entry is! Map) throw const FormatException('出站必须是 JSON 对象');
        final out = Map<String, dynamic>.from(entry);
        out['protocol'] = ProtocolCatalog.canonical(
          out['protocol'] as String? ?? '',
        );
        ProtocolCatalog.validate(out);
        // Cross-outbound chains cannot survive importing a single outbound.
        if (out.containsKey('proxySettings') ||
            out.containsKey('sendThrough') ||
            ((out['streamSettings'] as Map?)?['sockopt'] as Map?)?.containsKey(
                  'dialerProxy',
                ) ==
                true) {
          throw const FormatException('不支持依赖其他出站或固定网卡的配置');
        }
        final p = Profile.create(out['tag'] as String? ?? '导入节点', out);
        _validate(p);
        profiles.add(p);
      }
      if (profiles.isEmpty) throw const FormatException('未找到可用的代理出站');
      return profiles;
    }
    if (!text.contains('://')) text = _decode(text).trim();
    final lines = const LineSplitter()
        .convert(text)
        .where((s) => s.trim().isNotEmpty);
    final result = <Profile>[];
    for (final line in lines) {
      try {
        final p = _link(line.trim());
        _validate(p);
        result.add(p);
      } on Object {
        // Do not put the original URI (which contains credentials) into errors.
        throw FormatException('第 ${result.length + 1} 个节点格式无效或包含暂不支持的协议参数');
      }
    }
    if (result.isEmpty) throw const FormatException('订阅内容中没有节点');
    return result;
  }

  static void _validate(Profile p) => ProtocolCatalog.validate(p.outbound);

  static Profile _link(String text) {
    final scheme = Uri.tryParse(text)?.scheme;
    if ([
      'http',
      'https',
      'socks',
      'socks5',
      'hysteria2',
      'hy2',
      'hysteria',
      'wireguard',
      'wg',
      'masque',
    ].contains(scheme)) {
      return _otherLink(text);
    }
    if (text.startsWith('vmess://')) {
      final v = jsonDecode(_decode(text.substring(8))) as Map<String, dynamic>;
      final q = <String, String>{
        'type': '${v['net'] ?? 'tcp'}',
        'path': '${v['path'] ?? ''}',
        'host': '${v['host'] ?? ''}',
        'sni': '${v['sni'] ?? ''}',
        'security': v['tls'] == 'tls' ? 'tls' : 'none',
        'serviceName': '${v['path'] ?? ''}',
      };
      if (int.tryParse('${v['aid'] ?? 0}') != 0 ||
          !['none', ''].contains(v['type'] ?? 'none')) {
        throw const FormatException('不支持旧版 VMess 或伪装头');
      }
      return Profile.create('${v['ps'] ?? v['add']}', {
        'protocol': 'vmess',
        'settings': {
          'vnext': [
            {
              'address': v['add'],
              'port': int.parse('${v['port']}'),
              'users': [
                {'id': v['id'], 'security': v['scy'] ?? 'auto'},
              ],
            },
          ],
        },
        'streamSettings': _stream(q),
      });
    }
    if (text.startsWith('ss://')) {
      var body = text.substring(5);
      final fragment = body.indexOf('#');
      final name = fragment < 0
          ? 'Shadowsocks'
          : Uri.decodeComponent(body.substring(fragment + 1));
      if (fragment >= 0) body = body.substring(0, fragment);
      if (body.contains('?')) throw const FormatException('不支持 SIP003 插件');
      if (!body.contains('@')) body = _decode(body);
      final uri = Uri.parse('ss://$body');
      var auth = Uri.decodeComponent(uri.userInfo);
      if (!auth.contains(':')) auth = _decode(auth);
      final split = auth.indexOf(':');
      if (split < 1) throw const FormatException('缺少密码');
      return Profile.create(name, {
        'protocol': 'shadowsocks',
        'settings': {
          'servers': [
            {
              'address': _host(uri),
              'port': uri.port,
              'method': auth.substring(0, split),
              'password': auth.substring(split + 1),
            },
          ],
        },
      });
    }
    final u = Uri.parse(text);
    if (!['vless', 'trojan'].contains(u.scheme)) {
      throw const FormatException('不支持的协议');
    }
    if (!u.hasPort || u.userInfo.isEmpty) {
      throw const FormatException('缺少端口或凭据');
    }
    final q = u.queryParameters;
    if ((q['headerType'] ?? 'none') != 'none') {
      throw const FormatException('不支持伪装头');
    }
    final credentials = Uri.decodeComponent(u.userInfo);
    final settings = u.scheme == 'vless'
        ? {
            'vnext': [
              {
                'address': _host(u),
                'port': u.port,
                'users': [
                  {
                    'id': credentials,
                    'encryption': q['encryption'] ?? 'none',
                    if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow'],
                  },
                ],
              },
            ],
          }
        : {
            'servers': [
              {'address': _host(u), 'port': u.port, 'password': credentials},
            ],
          };
    return Profile.create(
      u.fragment.isEmpty ? _host(u) : Uri.decodeComponent(u.fragment),
      {
        'protocol': u.scheme,
        'settings': settings,
        if ((q['type'] ?? '') == 'xdrive')
          'mux': {
            'enabled': true,
            'concurrency': int.tryParse(q['concurrency'] ?? '') ?? 128,
          },
        'streamSettings': _stream({
          ...q,
          'security': q['security'] ?? (u.scheme == 'trojan' ? 'tls' : 'none'),
        }),
      },
    );
  }

  static String _host(Uri uri) => uri.host.replaceAll(RegExp(r'^\[|\]$'), '');

  static Map<String, dynamic> _stream(Map<String, String> q) {
    final rawNetwork = q['type'] ?? 'tcp';
    final network = ProtocolCatalog.networkAliases[rawNetwork] ?? rawNetwork;
    final security = q['security'] ?? 'none';
    if (!ProtocolCatalog.networks.contains(network) ||
        !['none', 'tls', 'reality'].contains(security)) {
      throw const FormatException('不支持的传输方式');
    }
    if (network == 'kcp' && (q['seed'] ?? '').isNotEmpty) {
      throw const FormatException('此内核版本请使用 FinalMask 配置 mKCP 加密');
    }
    if (q['allowInsecure'] == '1' || q['allowInsecure'] == 'true') {
      throw const FormatException('不支持关闭证书校验');
    }
    return {
      'network': network,
      'security': security,
      if (q.containsKey('finalmask')) 'finalmask': jsonDecode(q['finalmask']!),
      if (['kcp', 'hysteria', 'masque', 'xdrive'].contains(network))
        '${network}Settings': q.containsKey('${network}Settings')
            ? jsonDecode(q['${network}Settings']!)
            : <String, dynamic>{},
      if (security == 'tls')
        'tlsSettings': {
          if ((q['sni'] ?? '').isNotEmpty) 'serverName': q['sni'],
          'fingerprint': q['fp'] ?? 'chrome',
          if ((q['alpn'] ?? '').isNotEmpty) 'alpn': q['alpn']!.split(','),
        },
      if (security == 'reality')
        'realitySettings': {
          'serverName': q['sni'] ?? '',
          'fingerprint': q['fp'] ?? 'chrome',
          'publicKey': q['pbk'] ?? '',
          'shortId': q['sid'] ?? '',
          'spiderX': q['spx'] ?? '/',
        },
      if (network == 'ws')
        'wsSettings': {
          'path': (q['path'] ?? '').isEmpty ? '/' : q['path'],
          if ((q['host'] ?? '').isNotEmpty) 'headers': {'Host': q['host']},
        },
      if (network == 'grpc')
        'grpcSettings': {
          'serviceName': q['serviceName'] ?? '',
          'multiMode': q['mode'] == 'multi',
        },
      if (network == 'xhttp' || network == 'httpupgrade')
        '${network}Settings': {
          'path': (q['path'] ?? '').isEmpty ? '/' : q['path'],
          'host': q['host'] ?? '',
          if (network == 'xhttp') 'mode': q['mode'] ?? 'auto',
          if (network == 'xhttp' && q.containsKey('extra'))
            'extra': jsonDecode(q['extra']!),
        },
    };
  }

  static Profile _otherLink(String text) {
    final uri = Uri.parse(text), q = Uri.parse(text).queryParameters;
    final scheme = uri.scheme;
    if (q['insecure'] == '1' ||
        q['allowInsecure'] == '1' ||
        q['allowInsecure'] == 'true') {
      throw const FormatException('不能关闭证书校验');
    }
    final protocol = switch (scheme) {
      'https' => 'http',
      'socks5' => 'socks',
      'hy2' || 'hysteria2' => 'hysteria',
      'wg' => 'wireguard',
      _ => scheme,
    };
    final name = uri.fragment.isEmpty
        ? _host(uri)
        : Uri.decodeComponent(uri.fragment);
    var auth = Uri.decodeComponent(uri.userInfo);
    if (protocol == 'socks' && auth.isNotEmpty && !auth.contains(':')) {
      try {
        auth = _decode(auth);
      } on FormatException {
        /* username-only */
      }
    }
    final split = auth.indexOf(':');
    final username = split < 0 ? auth : auth.substring(0, split);
    final password = split < 0 ? '' : auth.substring(split + 1);
    if (protocol == 'http' || protocol == 'socks') {
      if (uri.path.isNotEmpty && uri.path != '/') {
        throw const FormatException('订阅网址请在订阅页添加');
      }
      return Profile.create(name, {
        'protocol': protocol,
        'settings': {
          'address': _host(uri),
          'port': uri.hasPort
              ? uri.port
              : scheme == 'https'
              ? 443
              : protocol == 'http'
              ? 80
              : 1080,
          if (auth.isNotEmpty) 'user': username,
          if (auth.isNotEmpty) 'pass': password,
        },
        'streamSettings': _stream({
          ...q,
          'security': q['security'] ?? (scheme == 'https' ? 'tls' : 'none'),
        }),
      });
    }
    if (protocol == 'hysteria') {
      if (q.containsKey('mport')) {
        throw const FormatException('多端口跳跃请通过完整 JSON 配置');
      }
      final obfs = q['obfs'];
      if (obfs != null && obfs != 'salamander' && obfs != 'none') {
        throw const FormatException('不支持此 obfs');
      }
      return Profile.create(name, {
        'protocol': 'hysteria',
        'settings': {
          'version': 2,
          'address': _host(uri),
          'port': uri.hasPort ? uri.port : 443,
        },
        'streamSettings': {
          ..._stream({...q, 'type': 'hysteria', 'security': 'tls'}),
          'hysteriaSettings': {'version': 2, 'auth': auth},
          if (obfs == 'salamander')
            'finalmask': {
              'udp': [
                {
                  'type': 'salamander',
                  'settings': {'password': q['obfs-password'] ?? ''},
                },
              ],
            },
        },
      });
    }
    if (protocol == 'wireguard') {
      final addresses = (q['address'] ?? '10.0.0.2/32').split(',');
      return Profile.create(name, {
        'protocol': 'wireguard',
        'settings': {
          'secretKey': auth,
          'address': addresses,
          'noKernelTun': true,
          'mtu': int.tryParse(q['mtu'] ?? '') ?? 1420,
          if (q.containsKey('reserved'))
            'reserved': q['reserved']!.split(',').map(int.parse).toList(),
          'peers': [
            {
              'publicKey': q['publickey'] ?? q['publicKey'] ?? '',
              'endpoint':
                  '${_host(uri).contains(':') ? '[${_host(uri)}]' : _host(uri)}:${uri.hasPort ? uri.port : 51820}',
              if (q.containsKey('presharedkey'))
                'preSharedKey': q['presharedkey'],
              'allowedIPs': (q['allowedIPs'] ?? '0.0.0.0/0,::/0').split(','),
            },
          ],
        },
      });
    }
    return Profile.create(name, {
      'protocol': 'masque',
      'settings': {'address': _host(uri), 'port': uri.hasPort ? uri.port : 443},
      'streamSettings': {
        ..._stream({...q, 'type': 'masque', 'security': 'tls'}),
        'masqueSettings': {
          if (username.isNotEmpty) 'user': username,
          if (password.isNotEmpty) 'pass': password,
          if (q.containsKey('host')) 'host': q['host'],
          if (q.containsKey('path')) 'path': q['path'],
        },
      },
    });
  }
}
