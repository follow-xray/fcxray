import 'dart:convert';

/// Matches the outbound registry in the pinned Xray-core infra/conf/xray.go.
/// xdrive is a VLESS transport, not an outbound protocol.
class ProtocolCatalog {
  static const protocols = [
    'vless',
    'vmess',
    'trojan',
    'shadowsocks',
    'socks',
    'http',
    'wireguard',
    'hysteria',
    'masque',
    'freedom',
    'blackhole',
    'dns',
    'loopback',
  ];
  static const aliases = {'direct': 'freedom', 'block': 'blackhole'};
  static const remote = [
    'vless',
    'vmess',
    'trojan',
    'shadowsocks',
    'socks',
    'http',
    'hysteria',
    'masque',
  ];
  static const utility = ['freedom', 'blackhole', 'dns', 'loopback'];
  static const networkAliases = {
    'raw': 'tcp',
    'mkcp': 'kcp',
    'websocket': 'ws',
    'splithttp': 'xhttp',
  };
  static const networks = [
    'tcp',
    'raw',
    'ws',
    'grpc',
    'xhttp',
    'httpupgrade',
    'kcp',
    'hysteria',
    'masque',
    'xdrive',
  ];
  static String canonical(String protocol) =>
      aliases[protocol.toLowerCase()] ?? protocol.toLowerCase();
  static String network(Map stream) {
    final value = '${stream['method'] ?? stream['network'] ?? 'tcp'}'
        .toLowerCase();
    return networkAliases[value] ?? value;
  }

  static Map<String, dynamic> flatten(Map<String, dynamic> outbound) {
    final out = jsonDecode(jsonEncode(outbound)) as Map<String, dynamic>;
    out['protocol'] = canonical(out['protocol'] as String);
    final settings = Map<String, dynamic>.from(out['settings'] as Map? ?? {});
    if (remote.contains(out['protocol']) && settings['address'] is! String) {
      final servers = (settings['vnext'] ?? settings['servers']) as List? ?? [];
      if (servers.isNotEmpty) {
        final server = Map<String, dynamic>.from(servers.first as Map);
        final users = server.remove('users') as List? ?? [];
        settings.remove('vnext');
        settings.remove('servers');
        settings.addAll(server);
        if (users.isNotEmpty) {
          settings.addAll(Map<String, dynamic>.from(users.first as Map));
        }
      }
    }
    out['settings'] = settings;
    return out;
  }

  static ({String host, int port}) endpoint(Map<String, dynamic> out) {
    final protocol = canonical(out['protocol'] as String? ?? '');
    final settings = out['settings'] as Map? ?? {};
    if (protocol == 'wireguard') {
      final peers = settings['peers'] as List? ?? [];
      final endpoint = peers.isEmpty
          ? ''
          : '${(peers.first as Map)['endpoint'] ?? ''}';
      final uri = Uri.tryParse('udp://$endpoint');
      return (
        host: uri?.host.replaceAll(RegExp(r'^\[|\]$'), '') ?? '',
        port: uri?.hasPort == true ? uri!.port : 0,
      );
    }
    if (settings['address'] is String) {
      return (
        host: settings['address'] as String,
        port: (settings['port'] as num?)?.toInt() ?? 0,
      );
    }
    final servers = (settings['vnext'] ?? settings['servers']) as List? ?? [];
    if (servers.isNotEmpty && servers.first is Map) {
      final server = servers.first as Map;
      return (
        host: '${server['address'] ?? ''}',
        port: (server['port'] as num?)?.toInt() ?? 0,
      );
    }
    if (protocol == 'dns') {
      return (
        host: '${settings['rewriteAddress'] ?? '内置 DNS'}',
        port: (settings['rewritePort'] as num?)?.toInt() ?? 53,
      );
    }
    return (
      host: switch (protocol) {
        'freedom' => '系统直连',
        'blackhole' => '阻断流量',
        'loopback' => '回注 ${settings['inboundTag'] ?? ''}',
        _ => protocol,
      },
      port: 0,
    );
  }

  static void validate(Map<String, dynamic> out) {
    final protocol = canonical(out['protocol'] as String? ?? '');
    if (!protocols.contains(protocol)) {
      throw FormatException(
        protocol == 'xdrive'
            ? 'xdrive 是 VLESS 的传输方式，请使用 vless + xdriveSettings'
            : '当前内核不支持出站协议 $protocol',
      );
    }
    if (out['settings'] != null && out['settings'] is! Map) {
      throw const FormatException('settings 必须是 JSON 对象');
    }
    if (remote.contains(protocol) || protocol == 'wireguard') {
      final target = endpoint(out);
      if (target.host.isEmpty || target.port < 1 || target.port > 65535) {
        throw const FormatException('服务器地址或端口无效');
      }
    }
    final settings = out['settings'] as Map? ?? {};
    if (protocol == 'loopback' &&
        ('${settings['inboundTag'] ?? ''}'.trim().isEmpty ||
            [
              'tun-in',
              'socks-in',
              'http-in',
            ].contains(settings['inboundTag']))) {
      throw const FormatException('回注标签不能为空或与客户端入口同名');
    }
    for (final key in ['vnext', 'servers']) {
      if (settings[key] is List && (settings[key] as List).length != 1) {
        throw const FormatException('当前内核每个出站只接受一个服务器，请拆分成多个节点');
      }
    }
    if (out['streamSettings'] != null && out['streamSettings'] is! Map) {
      throw const FormatException('streamSettings 必须是 JSON 对象');
    }
    final stream = out['streamSettings'] as Map? ?? {};
    final transport = network(stream);
    if (!networks.contains(transport)) {
      throw FormatException('当前内核不支持传输方式 $transport');
    }
    if (protocol == 'hysteria' &&
        (settings['version'] != 2 || transport != 'hysteria')) {
      throw const FormatException('Hysteria 出站需要 version: 2 和 hysteria 传输');
    }
    if (transport == 'masque' && protocol != 'masque') {
      throw const FormatException('masque 传输只能用于 MASQUE 出站');
    }
    if (protocol == 'masque' && transport != 'masque') {
      throw const FormatException('MASQUE 出站需要 masque 传输');
    }
    if (transport == 'xdrive') {
      final flat = flatten(out)['settings'] as Map;
      final mux = out['mux'] as Map? ?? {};
      if (protocol != 'vless' ||
          '${flat['encryption'] ?? ''}'.isEmpty ||
          flat['encryption'] == 'none') {
        throw const FormatException('xdrive 需要 VLESS 和有效的 VLESS encryption');
      }
      if ('${flat['flow'] ?? ''}'.isNotEmpty ||
          mux['enabled'] != true ||
          (mux['concurrency'] as num? ?? 8) < 0 ||
          (mux['xudpConcurrency'] as num? ?? 0) < 0 ||
          mux['xudpProxyUDP443'] == 'skip') {
        throw const FormatException(
          'xdrive 需要启用 Mux、非负并发数，不能使用 flow 或跳过 UDP/443',
        );
      }
      final drive = stream['xdriveSettings'] as Map? ?? {};
      if ('${drive['remoteFolder'] ?? ''}'.trim().isEmpty) {
        throw const FormatException('xdrive 需要 remoteFolder');
      }
      if (![
        'local',
        'google-drive',
        'Google Drive',
        'template',
        's3',
      ].contains(drive['service'])) {
        throw const FormatException(
          'xdrive service 应为 local、google-drive、template 或 s3',
        );
      }
    }
  }
}
