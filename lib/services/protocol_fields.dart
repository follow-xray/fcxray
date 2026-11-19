import 'dart:convert';
import 'protocol_catalog.dart';

class ProtocolField {
  const ProtocolField(
    this.id,
    this.path,
    this.label,
    this.help, {
    this.kind = 'text',
    this.defaultValue = '',
    this.required = false,
    this.choices = const [],
  });
  final String id, path, label, help, kind, defaultValue;
  final bool required;
  final List<String> choices;
}

class ProtocolFields {
  static const protocolFields = <String, List<ProtocolField>>{
    'http': [
      ProtocolField(
        'proxyUser',
        'settings.user',
        '代理用户名',
        'HTTP 代理认证用户名；服务器无需认证时留空。',
      ),
      ProtocolField(
        'proxyPass',
        'settings.pass',
        '代理密码',
        'HTTP 代理密码，需与用户名一起填写。',
        kind: 'secret',
      ),
      ProtocolField(
        'proxyHeaders',
        'settings.headers',
        'HTTP 代理请求头 JSON',
        '发给上游代理的附加字符串请求头对象；不是 WebSocket 请求头。',
        kind: 'object',
      ),
    ],
    'socks': [
      ProtocolField(
        'proxyUser',
        'settings.user',
        '代理用户名',
        'SOCKS5 认证用户名；无需认证时留空。',
      ),
      ProtocolField(
        'proxyPass',
        'settings.pass',
        '代理密码',
        'SOCKS5 认证密码。',
        kind: 'secret',
      ),
    ],
    'wireguard': [
      ProtocolField(
        'wgKey',
        'settings.secretKey',
        'WireGuard 私钥',
        '本机客户端私钥，Base64 或 64 位十六进制；仅保存在安全存储。',
        kind: 'secret',
        required: true,
      ),
      ProtocolField(
        'wgAddress',
        'settings.address',
        '隧道地址',
        '逗号分隔的隧道 IP/CIDR，如 10.0.0.2/32,fd00::2/128，需由服务端分配。',
        kind: 'list',
        defaultValue: '10.0.0.2/32',
      ),
      ProtocolField(
        'wgPeerKey',
        'settings.peers.0.publicKey',
        'Peer 公钥',
        '服务端 WireGuard 公钥。',
        required: true,
      ),
      ProtocolField(
        'wgEndpoint',
        'settings.peers.0.endpoint',
        'Peer Endpoint',
        '服务端域名:端口或 [IPv6]:端口。多 Peer 配置可在完整 JSON 中编辑。',
        required: true,
      ),
      ProtocolField(
        'wgPsk',
        'settings.peers.0.preSharedKey',
        '预共享密钥',
        '可选的 PSK，必须与服务端一致。',
        kind: 'secret',
      ),
      ProtocolField(
        'wgAllowed',
        'settings.peers.0.allowedIPs',
        'Allowed IPs',
        '此 Peer 允许的目标网段，逗号分隔；全量隧道通常使用 0.0.0.0/0,::/0。',
        kind: 'list',
        defaultValue: '0.0.0.0/0,::/0',
      ),
      ProtocolField(
        'wgKeepAlive',
        'settings.peers.0.keepAlive',
        'Keepalive（秒）',
        '维护 NAT 映射；0 表示关闭，常用 25。',
        kind: 'uint',
        defaultValue: '25',
      ),
      ProtocolField(
        'wgMtu',
        'settings.mtu',
        'WireGuard MTU',
        '用户态隧道 MTU，默认 1420。',
        kind: 'uint',
        defaultValue: '1420',
      ),
      ProtocolField(
        'wgReserved',
        'settings.reserved',
        'Reserved JSON',
        '可选的 3 个字节数组，如 [0,0,0]；仅在服务商要求时设置。',
        kind: 'array',
      ),
      ProtocolField(
        'wgDNS',
        'settings.remoteDNS',
        '远端 DNS',
        '通过 WireGuard 隧道解析的 DNS IP，逗号分隔。',
        kind: 'list',
        defaultValue: '1.1.1.1',
      ),
      ProtocolField(
        'wgUserSpace',
        'settings.noKernelTun',
        '用户态 WireGuard',
        'true 使用用户态网络栈，避免为出站额外创建系统 TUN。',
        kind: 'bool',
        defaultValue: 'true',
      ),
    ],
    'hysteria': [
      ProtocolField(
        'hyDNSNote',
        'settings.version',
        'Hysteria 版本',
        '当前 Xray 的 Hysteria 出站实现为 Hysteria 2。',
        kind: 'uint',
        defaultValue: '2',
      ),
    ],
    'masque': [
      ProtocolField(
        'masqueDNS',
        'settings.remoteDNS',
        'MASQUE 远端 DNS',
        '通过 CONNECT-IP 隧道解析域名的 DNS IP，逗号分隔。',
        kind: 'list',
        defaultValue: '1.1.1.1',
      ),
    ],
    'freedom': [
      ProtocolField(
        'directStrategy',
        'settings.targetStrategy',
        '目标解析策略',
        'freedom/direct 是直连出口，无远端代理服务器。AsIs 使用系统解析；其他模式使用内置 DNS。',
        defaultValue: 'AsIs',
        choices: [
          'AsIs',
          'UseIP',
          'UseIPv4',
          'UseIPv6',
          'ForceIP',
          'ForceIPv4',
          'ForceIPv6',
        ],
      ),
      ProtocolField(
        'directRedirect',
        'settings.redirect',
        '重定向地址',
        '可选，强制将连接发往指定 host:port；留空保留原目标。',
      ),
      ProtocolField(
        'directRules',
        'settings.finalRules',
        'Final rules JSON',
        '直连出站的最终允许/阻止规则数组；由内核校验。',
        kind: 'array',
      ),
    ],
    'blackhole': [
      ProtocolField(
        'blockResponse',
        'settings.response',
        '阻断响应 JSON',
        'blackhole/block 是阻断出口，不是远端服务器；例如 {"type":"none"} 或 {"type":"http"}。',
        kind: 'object',
        defaultValue: '{"type":"none"}',
      ),
    ],
    'dns': [
      ProtocolField(
        'dnsNetwork',
        'settings.rewriteNetwork',
        'DNS 上游传输',
        'dns 是仅处理 DNS 的专用出站，不能承载普通网页流量。',
        defaultValue: 'udp',
        choices: ['udp', 'tcp'],
      ),
      ProtocolField(
        'dnsAddress',
        'settings.rewriteAddress',
        'DNS 上游地址',
        '覆盖 DNS 请求的上游地址；留空使用原目的地址。',
        defaultValue: '1.1.1.1',
      ),
      ProtocolField(
        'dnsPort',
        'settings.rewritePort',
        'DNS 上游端口',
        '覆盖 DNS 上游端口，通常为 53。',
        kind: 'uint',
        defaultValue: '53',
      ),
      ProtocolField(
        'dnsRules',
        'settings.rules',
        'DNS 规则 JSON',
        'DNS query type/domain/action 规则数组；完整格式由 Xray 校验。',
        kind: 'array',
      ),
    ],
    'loopback': [
      ProtocolField(
        'loopbackTag',
        'settings.inboundTag',
        '回注入站标签',
        'loopback 将流量重新送入路由。作为独立节点使用时，客户端为此标签添加直连出口，避免无限回环。',
        defaultValue: 'fcxray-loopback',
        required: true,
      ),
      ProtocolField(
        'loopbackSniff',
        'settings.sniffing',
        '回注嗅探 JSON',
        '可选的 sniffing 对象；用于回注流量的重新识别。',
        kind: 'object',
      ),
    ],
  };

  static const transportFields = <String, List<ProtocolField>>{
    'kcp': [
      ProtocolField(
        'kcpMtu',
        'streamSettings.kcpSettings.mtu',
        'mKCP MTU',
        'UDP 传输 MTU，至少 21；留空使用内核默认。',
        kind: 'uint',
      ),
      ProtocolField(
        'kcpTti',
        'streamSettings.kcpSettings.tti',
        'mKCP TTI（毫秒）',
        '发送间隔，10–1000；留空使用默认值。',
        kind: 'uint',
      ),
      ProtocolField(
        'kcpUp',
        'streamSettings.kcpSettings.uplinkCapacity',
        'mKCP 上行容量',
        '以 MB/s 表示的上行容量，留空使用默认值。',
        kind: 'uint',
      ),
      ProtocolField(
        'kcpDown',
        'streamSettings.kcpSettings.downlinkCapacity',
        'mKCP 下行容量',
        '以 MB/s 表示的下行容量，留空使用默认值。',
        kind: 'uint',
      ),
      ProtocolField(
        'kcpCwnd',
        'streamSettings.kcpSettings.cwndMultiplier',
        '拥塞窗口倍率',
        '至少为 1，留空使用默认值。',
        kind: 'uint',
      ),
      ProtocolField(
        'kcpWindow',
        'streamSettings.kcpSettings.maxSendingWindow',
        '最大发送窗口',
        '至少容纳一个 MTU，留空使用默认值。',
        kind: 'uint',
      ),
    ],
    'hysteria': [
      ProtocolField(
        'hyVersion',
        'streamSettings.hysteriaSettings.version',
        'Hysteria 传输版本',
        '固定为 2；该传输也可用于其他 Xray 出站协议。',
        kind: 'uint',
        defaultValue: '2',
      ),
      ProtocolField(
        'hyAuth',
        'streamSettings.hysteriaSettings.auth',
        'Hysteria Auth',
        '与服务端一致的认证字符串。',
        kind: 'secret',
      ),
      ProtocolField(
        'hyIdle',
        'streamSettings.hysteriaSettings.udpIdleTimeout',
        'UDP 空闲超时（秒）',
        '允许 2–600，0 或留空使用内核默认值。',
        kind: 'uint',
      ),
    ],
    'masque': [
      ProtocolField(
        'mqHost',
        'streamSettings.masqueSettings.host',
        'MASQUE Host',
        '覆盖 CONNECT-IP HTTP authority；留空采用内核默认值。',
      ),
      ProtocolField(
        'mqPath',
        'streamSettings.masqueSettings.path',
        'CONNECT-IP 路径',
        '可选 URI template，支持 {target} 和 {ipproto}；留空使用默认路径。',
      ),
      ProtocolField(
        'mqUser',
        'streamSettings.masqueSettings.user',
        'MASQUE 用户名',
        'Basic Auth 用户名；启用 WARP 时不要填写。',
      ),
      ProtocolField(
        'mqPass',
        'streamSettings.masqueSettings.pass',
        'MASQUE 密码',
        'Basic Auth 密码；启用 WARP 时不要填写。',
        kind: 'secret',
      ),
      ProtocolField(
        'mqHeaders',
        'streamSettings.masqueSettings.headers',
        'MASQUE 请求头 JSON',
        '可选额外请求头对象；不能与内核保留头冲突。',
        kind: 'object',
      ),
      ProtocolField(
        'mqWarp',
        'streamSettings.masqueSettings.warp',
        'WARP JSON',
        '可选 privateKey/publicKey/address 对象；使用 WARP 时与 user/pass 互斥。',
        kind: 'object',
      ),
      ProtocolField(
        'mqXmux',
        'streamSettings.masqueSettings.xmux',
        'MASQUE Xmux JSON',
        '可选 HTTP 连接复用参数对象。',
        kind: 'object',
      ),
    ],
    'xdrive': [
      ProtocolField(
        'xdService',
        'streamSettings.xdriveSettings.service',
        'xdrive 存储服务',
        'xdrive 是 VLESS 传输，需要 VLESS encryption、启用 Mux、清空 flow。local 用于本地共享目录；其他服务需要相应凭据。',
        defaultValue: 'google-drive',
        choices: ['google-drive', 's3', 'template', 'local'],
      ),
      ProtocolField(
        'xdFolder',
        'streamSettings.xdriveSettings.remoteFolder',
        '远端目录 / Folder ID',
        'Google Drive 填 folder ID；S3 填相对前缀；template 填模板目录；local 填应用可访问的绝对目录。',
        required: true,
      ),
      ProtocolField(
        'xdSecrets',
        'streamSettings.xdriveSettings.secrets',
        '存储凭据 JSON 数组',
        'Google Drive：[ClientID, ClientSecret, RefreshToken]；S3：[AccessKeyID, SecretAccessKey, 可选 SessionToken]；template 按 {secret0} 等索引使用。',
        kind: 'secrets',
      ),
      ProtocolField(
        'xdS3',
        'streamSettings.xdriveSettings.s3',
        'S3 参数 JSON',
        'service=s3 时必填：endpoint、region、bucket、pathStyle。endpoint 为 http(s) URL；remoteFolder 为非空相对前缀。',
        kind: 'object',
      ),
      ProtocolField(
        'xdTemplate',
        'streamSettings.xdriveSettings.template',
        'HTTP / WebDAV 模板 JSON',
        'service=template 时必填完整模板对象，含 put/get/delete/list 等请求及认证。支持 {folder}/{name}/{secret0} 等变量。',
        kind: 'object',
      ),
      ProtocolField(
        'xdSegment',
        'streamSettings.xdriveSettings.segmentBytes',
        '分片大小（字节）',
        '留空使用内核默认分片大小。更大的分片会改变延迟和存储请求次数。',
        kind: 'uint',
      ),
      ProtocolField(
        'xdFlush',
        'streamSettings.xdriveSettings.flushIntervalMs',
        '刷新间隔（毫秒）',
        '缓冲数据写入存储的间隔；留空使用内核默认值。',
        kind: 'uint',
      ),
      ProtocolField(
        'xdPoll',
        'streamSettings.xdriveSettings.pollIntervalMs',
        '轮询间隔（毫秒）',
        '查询远端数据的初始间隔；留空使用默认值。',
        kind: 'uint',
      ),
      ProtocolField(
        'xdMaxPoll',
        'streamSettings.xdriveSettings.maxPollIntervalMs',
        '最大轮询间隔（毫秒）',
        '退避轮询间隔上限，留空使用默认值。',
        kind: 'uint',
      ),
      ProtocolField(
        'xdTTL',
        'streamSettings.xdriveSettings.sessionTtlSeconds',
        '会话 TTL（秒）',
        '存储传输会话的存活时间，留空使用默认值。',
        kind: 'uint',
      ),
      ProtocolField(
        'xdConcurrency',
        'streamSettings.xdriveSettings.concurrency',
        '存储请求并发',
        'xdrive 存储请求并发数，不同于外层 Mux 并发。',
        kind: 'uint',
      ),
      ProtocolField(
        'xdEager',
        'streamSettings.xdriveSettings.eagerWindowMs',
        'Eager window（毫秒）',
        '活跃阶段的快速读取窗口，留空使用内核默认值。',
        kind: 'uint',
      ),
      ProtocolField(
        'xdHole',
        'streamSettings.xdriveSettings.holeTimeoutMs',
        '缺片等待超时（毫秒）',
        '等待缺失分片的超时，留空使用内核默认值。',
        kind: 'uint',
      ),
      ProtocolField(
        'xdXmux',
        'streamSettings.xdriveSettings.xmux',
        'xdrive Xmux JSON',
        'HTTP 连接池参数；maxConnections 与 maxConcurrency 不能同时配置正值。',
        kind: 'object',
      ),
    ],
  };
  static const common = [
    ProtocolField(
      'finalmask',
      'streamSettings.finalmask',
      'FinalMask JSON',
      '可配置 TCP/UDP 掩码与 quicParams。Hysteria/MASQUE/xdrive 的 QUIC 调优也在此对象中；不支持外部脚本。',
      kind: 'object',
    ),
    ProtocolField(
      'sockopt',
      'streamSettings.sockopt',
      'Socket 选项 JSON',
      '可选 Xray sockopt 对象。指定固定网卡会影响 TUN 自动出站绑定，请按实际网络配置。',
      kind: 'object',
    ),
  ];
  static Iterable<ProtocolField> get all sync* {
    for (final fields in protocolFields.values) {
      yield* fields;
    }
    for (final fields in transportFields.values) {
      yield* fields;
    }
    yield* common;
  }

  static Object? getPath(Map root, String path) {
    dynamic value = root;
    for (final part in path.split('.')) {
      if (value is Map) {
        value = value[part];
      } else if (value is List) {
        final i = int.tryParse(part);
        value = i != null && i < value.length ? value[i] : null;
      } else {
        return null;
      }
    }
    return value;
  }

  static void setPath(Map<String, dynamic> root, String path, Object? value) {
    final parts = path.split('.');
    dynamic cursor = root;
    for (var i = 0; i < parts.length - 1; i++) {
      final key = parts[i], next = parts[i + 1];
      if (cursor is Map) {
        cursor[key] ??= int.tryParse(next) != null
            ? <dynamic>[]
            : <String, dynamic>{};
        cursor = cursor[key];
      } else if (cursor is List) {
        final index = int.parse(key);
        while (cursor.length <= index) {
          cursor.add(<String, dynamic>{});
        }
        cursor = cursor[index];
      }
    }
    if (cursor is Map) {
      if (value == null) {
        cursor.remove(parts.last);
      } else {
        cursor[parts.last] = value;
      }
    }
  }

  static Map<String, String> fields(Map<String, dynamic> out) => {
    for (final field in all) field.id: _text(getPath(out, field.path), field),
  };
  static String _text(Object? value, ProtocolField field) {
    if (value == null) return field.defaultValue;
    if (field.kind == 'list' && value is List) return value.join(',');
    if (['object', 'array', 'secrets'].contains(field.kind)) {
      return jsonEncode(value);
    }
    return '$value';
  }

  static void apply(
    Map<String, dynamic> out,
    Map<String, String> values,
    Iterable<ProtocolField> fields,
  ) {
    for (final field in fields) {
      final raw = values[field.id] ?? field.defaultValue, text = raw.trim();
      if (text.isEmpty) {
        if (field.required) throw FormatException('请填写${field.label}');
        setPath(out, field.path, null);
        continue;
      }
      Object? value = raw;
      switch (field.kind) {
        case 'uint':
          final n = int.tryParse(text);
          if (n == null || n < 0 || n > 0xffffffff) {
            throw FormatException('${field.label}需要非负整数');
          }
          value = n;
        case 'bool':
          value = text == 'true';
        case 'list':
          value = text
              .split(RegExp(r'[,，\s]+'))
              .where((s) => s.isNotEmpty)
              .toList();
        case 'object':
          value = jsonDecode(text);
          if (value is! Map<String, dynamic>) {
            throw FormatException('${field.label}需要 JSON 对象');
          }
        case 'array':
          value = jsonDecode(text);
          if (value is! List) throw FormatException('${field.label}需要 JSON 数组');
        case 'secrets':
          value = jsonDecode(text);
          if (value is! List || value.any((e) => e is! String)) {
            throw FormatException('${field.label}需要字符串数组');
          }
        case 'secret':
          value = raw;
        default:
          value = text;
      }
      setPath(out, field.path, value);
    }
  }

  static String defaultNetwork(String protocol) => switch (protocol) {
    'hysteria' => 'hysteria',
    'masque' => 'masque',
    _ => 'tcp',
  };
  static String defaultSecurity(String protocol) =>
      ['trojan', 'hysteria', 'masque'].contains(protocol) ? 'tls' : 'none';
  static List<String> allowedNetworks(String protocol) => switch (protocol) {
    'hysteria' => ['hysteria'],
    'masque' => ['masque'],
    'wireguard' || 'freedom' || 'blackhole' || 'dns' || 'loopback' => ['tcp'],
    _ =>
      ProtocolCatalog.networks
          .where((n) => n != 'masque' && (n != 'xdrive' || protocol == 'vless'))
          .toList(),
  };
}
