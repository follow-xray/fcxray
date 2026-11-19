import 'dart:convert';
import '../models/profile.dart';
import 'protocol_catalog.dart';
import 'protocol_fields.dart';

class ManualProfile {
  static const basicProtocols = ['vless', 'vmess', 'trojan', 'shadowsocks'];
  static const protocols = ProtocolCatalog.protocols;
  static const networks = ProtocolCatalog.networks;
  static const ciphers = [
    'aes-128-gcm',
    'aes-256-gcm',
    'chacha20-ietf-poly1305',
    'xchacha20-ietf-poly1305',
    '2022-blake3-aes-128-gcm',
    '2022-blake3-aes-256-gcm',
    '2022-blake3-chacha20-poly1305',
  ];
  static Map<String, String> fields([Profile? profile]) {
    final out = profile == null
        ? <String, dynamic>{}
        : ProtocolCatalog.flatten(profile.outbound);
    final settings = out['settings'] as Map? ?? {};
    final servers =
        settings['vnext'] as List? ?? settings['servers'] as List? ?? [];
    final server = servers.isEmpty ? settings : servers.first as Map;
    final users = server['users'] as List? ?? [];
    final user = users.isEmpty ? settings : users.first as Map;
    final stream = out['streamSettings'] as Map? ?? {};
    final security =
        (stream['security'] as String? ??
                (profile?.protocol == 'trojan' ? 'tls' : 'none'))
            .toLowerCase();
    final secured = stream['${security}Settings'] as Map? ?? {};
    final network = ProtocolCatalog.network(stream);
    final transport = stream['${network}Settings'] as Map? ?? {};
    final headers = transport['headers'] as Map? ?? {};
    return {
      ...ProtocolFields.fields(out),
      'name': profile?.name ?? '',
      'protocol': profile?.protocol ?? 'vless',
      'address': '${server['address'] ?? ''}',
      'port': '${server['port'] ?? 443}',
      'credential': '${user['id'] ?? server['password'] ?? ''}',
      'encryption': '${user['encryption'] ?? 'none'}',
      'flow': '${user['flow'] ?? ''}',
      'cipher': '${user['security'] ?? 'auto'}',
      'method': '${server['method'] ?? 'aes-128-gcm'}',
      'network': network,
      'security': security,
      'sni': '${secured['serverName'] ?? ''}',
      'fingerprint': '${secured['fingerprint'] ?? 'chrome'}',
      'alpn': (secured['alpn'] as List? ?? []).join(','),
      'publicKey': '${secured['publicKey'] ?? secured['password'] ?? ''}',
      'shortId': '${secured['shortId'] ?? ''}',
      'spiderX': '${secured['spiderX'] ?? '/'}',
      'mldsa65Verify': '${secured['mldsa65Verify'] ?? ''}',
      'path': '${transport['path'] ?? '/'}',
      'host': '${transport['host'] ?? headers['Host'] ?? ''}',
      'serviceName': '${transport['serviceName'] ?? ''}',
      'authority': '${transport['authority'] ?? ''}',
      'multiMode': '${transport['multiMode'] ?? false}',
      'xhttpMode': '${transport['mode'] ?? 'auto'}',
      'extra': transport['extra'] == null
          ? ''
          : const JsonEncoder.withIndent('  ').convert(transport['extra']),
      'headers': headers.isEmpty
          ? ''
          : const JsonEncoder.withIndent('  ').convert(headers),
      'mux': '${(out['mux'] as Map?)?['enabled'] ?? false}',
      'concurrency': '${(out['mux'] as Map?)?['concurrency'] ?? 8}',
    };
  }

  static Profile build(Map<String, String> fields, {Profile? original}) {
    String v(String key) => fields[key]?.trim() ?? '';
    final protocol = v('protocol'),
        network = v('network'),
        security = v('security');
    if (!protocols.contains(protocol) ||
        !networks.contains(network) ||
        !['none', 'tls', 'reality'].contains(security)) {
      throw const FormatException('请选择支持的协议和传输方式');
    }
    if (v('name').isEmpty || v('name').length > 128) {
      throw const FormatException('节点名称需要 1–128 个字符');
    }
    final address = v('address').replaceAll(RegExp(r'^\[|\]$'), '');
    if (ProtocolCatalog.remote.contains(protocol) &&
        (address.isEmpty || address.contains(RegExp(r'[\s/\\]')))) {
      throw const FormatException('请输入服务器域名或 IP，不要包含协议前缀或路径');
    }
    final port = int.tryParse(v('port'));
    if (ProtocolCatalog.remote.contains(protocol) &&
        (port == null || port < 1 || port > 65535)) {
      throw const FormatException('端口必须为 1–65535');
    }
    final credential = ['vless', 'vmess'].contains(protocol)
        ? v('credential')
        : fields['credential'] ?? '';
    if (basicProtocols.contains(protocol) && credential.isEmpty) {
      throw const FormatException('请填写 UUID / 密码');
    }
    if (security == 'reality' && (v('publicKey').isEmpty || v('sni').isEmpty)) {
      throw const FormatException('REALITY 需要服务器名称和公钥');
    }
    if (protocol == 'vless' &&
        v('flow').isNotEmpty &&
        (!['tcp', 'raw'].contains(network) || security == 'none')) {
      throw const FormatException('Vision flow 需要 TCP/RAW 和 TLS 或 REALITY');
    }
    if (protocol == 'vless' && v('flow').isNotEmpty && v('mux') == 'true') {
      throw const FormatException('Vision flow 不能启用 Mux');
    }
    final out = original?.protocol == protocol
        ? ProtocolCatalog.flatten(original!.outbound)
        : <String, dynamic>{};
    final settings = Map<String, dynamic>.from(out['settings'] as Map? ?? {});
    if (ProtocolCatalog.remote.contains(protocol)) {
      settings.addAll({'address': address, 'port': port});
    }
    if (protocol == 'vless' || protocol == 'vmess') {
      settings['id'] = credential;
      if (protocol == 'vless') {
        settings['encryption'] = v('encryption').isEmpty
            ? 'none'
            : v('encryption');
        if (v('flow').isEmpty) {
          settings.remove('flow');
        } else {
          settings['flow'] = v('flow');
        }
      } else {
        settings['security'] = v('cipher');
        settings.remove('alterId');
      }
    } else if (protocol == 'trojan' || protocol == 'shadowsocks') {
      settings['password'] = credential;
      if (protocol == 'shadowsocks') settings['method'] = v('method');
    }
    out['settings'] = settings;
    ProtocolFields.apply(
      out,
      fields,
      ProtocolFields.protocolFields[protocol] ?? [],
    );
    if (protocol == 'hysteria') settings['version'] = 2;
    if (['http', 'socks'].contains(protocol) &&
        '${settings['user'] ?? ''}'.isEmpty &&
        '${settings['pass'] ?? ''}'.isNotEmpty) {
      throw const FormatException('代理密码需要配合用户名使用');
    }
    if (protocol == 'loopback' &&
        ['tun-in', 'socks-in', 'http-in'].contains(settings['inboundTag'])) {
      throw const FormatException('回注标签不能与客户端入口同名');
    }
    final oldStream = out['streamSettings'] as Map? ?? {};
    final stream = <String, dynamic>{
      ...oldStream,
      'network': network,
      'security': security,
    };
    stream.remove('method');
    for (final key in ['tlsSettings', 'realitySettings']) {
      stream.remove(key);
    }
    if (security != 'none') {
      final options = <String, dynamic>{
        ...Map<String, dynamic>.from(
          oldStream['${security}Settings'] as Map? ?? {},
        ),
      };
      options.remove('allowInsecure');
      options.remove('serverName');
      if (v('sni').isNotEmpty) options['serverName'] = v('sni');
      options['fingerprint'] = v('fingerprint');
      if (security == 'tls') {
        options.remove('alpn');
        if (v('alpn').isNotEmpty) {
          options['alpn'] = v(
            'alpn',
          ).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }
      } else {
        options.remove('password');
        options.addAll({
          'publicKey': v('publicKey'),
          'shortId': v('shortId'),
          'spiderX': v('spiderX'),
        });
        if (v('mldsa65Verify').isEmpty) {
          options.remove('mldsa65Verify');
        } else {
          options['mldsa65Verify'] = v('mldsa65Verify');
        }
      }
      stream['${security}Settings'] = options;
    }
    if (['grpc', 'ws', 'xhttp', 'httpupgrade'].contains(network)) {
      final transport = <String, dynamic>{
        ...Map<String, dynamic>.from(
          oldStream['${network}Settings'] as Map? ?? {},
        ),
      };
      if (network == 'grpc') {
        transport.addAll({
          'serviceName': v('serviceName'),
          'authority': v('authority'),
          'multiMode': v('multiMode') == 'true',
        });
      } else {
        transport['path'] = v('path').isEmpty ? '/' : v('path');
        if (network == 'ws') {
          final headers = v('headers').isEmpty
              ? <String, dynamic>{}
              : jsonDecode(v('headers'));
          if (headers is! Map<String, dynamic> ||
              headers.values.any((e) => e is! String)) {
            throw const FormatException('请求头应是字符串键值对 JSON 对象');
          }
          headers.remove('Host');
          if (v('host').isNotEmpty) headers['Host'] = v('host');
          transport['headers'] = headers;
        } else {
          transport['host'] = v('host');
        }
        if (network == 'xhttp') {
          transport['mode'] = v('xhttpMode');
          transport.remove('extra');
          if (v('extra').isNotEmpty) {
            final extra = jsonDecode(v('extra'));
            if (extra is! Map<String, dynamic>) {
              throw const FormatException('XHTTP extra 应为 JSON 对象');
            }
            transport['extra'] = extra;
          }
        }
      }
      stream['${network}Settings'] = transport;
    }
    out['streamSettings'] = stream;
    ProtocolFields.apply(
      out,
      fields,
      ProtocolFields.transportFields[network] ?? [],
    );
    ProtocolFields.apply(out, fields, ProtocolFields.common);
    if (network == 'hysteria') {
      ProtocolFields.setPath(out, 'streamSettings.hysteriaSettings.version', 2);
    }
    final concurrency = int.tryParse(v('concurrency'));
    if (v('mux') == 'true' &&
        (concurrency == null || concurrency < 1 || concurrency > 1024)) {
      throw const FormatException('Mux 并发数需要 1–1024');
    }
    out['mux'] = {
      ...Map<String, dynamic>.from(out['mux'] as Map? ?? {}),
      'enabled': v('mux') == 'true',
      'concurrency': concurrency ?? 8,
    };
    out['protocol'] = protocol;
    out['tag'] = 'proxy';
    ProtocolCatalog.validate(out);
    return Profile.create(v('name'), out);
  }
}
