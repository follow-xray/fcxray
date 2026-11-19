import 'calm_theme.dart';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../models/profile.dart';
import '../services/manual_profile.dart';
import '../services/protocol_catalog.dart';
import '../services/protocol_fields.dart';
import '../services/profile_importer.dart';
import 'help_fields.dart';

Future<void> showNodeEditor(
  BuildContext context,
  AppController controller, [
  Profile? profile,
]) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => NodeEditor(controller: controller, original: profile),
);

class NodeEditor extends StatefulWidget {
  const NodeEditor({
    super.key,
    required this.controller,
    this.original,
    this.template,
  });
  final AppController controller;
  final Profile? original;
  final Profile? template;
  @override
  State<NodeEditor> createState() => _NodeEditorState();
}

class _NodeEditorState extends State<NodeEditor> {
  late final Map<String, TextEditingController> fields;
  bool saving = false, reveal = false, rawMode = false;
  final raw = TextEditingController();
  String rawAtOpen = '';
  Profile? baseProfile;
  bool get realityTemplate =>
      widget.template?.outbound['streamSettings']?['security'] == 'reality';
  String? error;
  String value(String key) => fields[key]!.text;
  @override
  void initState() {
    super.initState();
    baseProfile = widget.original ?? widget.template;
    fields = ManualProfile.fields(
      baseProfile,
    ).map((k, v) => MapEntry(k, TextEditingController(text: v)));
    if (realityTemplate) {
      for (final key in [
        'address',
        'credential',
        'sni',
        'publicKey',
        'shortId',
      ]) {
        fields[key]!.clear();
      }
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    raw.dispose();
    super.dispose();
  }

  Widget text(
    String key,
    String label,
    String help, {
    bool secret = false,
    int lines = 1,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: fields[key],
      enabled: !saving,
      minLines: lines,
      maxLines: lines,
      obscureText: secret && !reveal,
      autocorrect: false,
      enableSuggestions: !secret,
      keyboardType: key == 'port' || key == 'concurrency'
          ? TextInputType.number
          : null,
      decoration: helpDecoration(label, help, hint: hint),
    ),
  );
  Widget select(
    String key,
    String label,
    String help,
    List<String> choices, {
    ValueChanged<String>? changed,
  }) {
    final current = value(key);
    final values = choices.contains(current) ? choices : [current, ...choices];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: HelpDropdown<String>(
        label: label,
        help: help,
        value: current,
        items: values
            .map(
              (v) => DropdownMenuItem(
                value: v,
                child: Text(v.isEmpty ? '不启用' : v),
              ),
            )
            .toList(),
        onChanged: saving
            ? null
            : (v) => setState(() {
                fields[key]!.text = v!;
                changed?.call(v);
              }),
      ),
    );
  }

  Widget section(String title) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 18),
    child: Row(
      children: [
        Container(
          width: 5,
          height: 18,
          decoration: BoxDecoration(
            color: Calm.of(context).iris,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Calm.of(context).iris,
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final protocol = value('protocol'),
        network = value('network'),
        security = value('security');
    return Dialog(
      child: SizedBox(
        width: 720,
        height: min(MediaQuery.sizeOf(context).height * .9, 850),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      realityTemplate
                          ? '新建 VLESS Vision TCP REALITY 节点'
                          : widget.original == null
                          ? '手动添加节点'
                          : widget.original!.subscriptionId == null
                          ? '编辑节点'
                          : '复制为手动节点',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (realityTemplate) ...[
                      text(
                        'address',
                        '服务器地址',
                        '填写服务端域名或 IP。',
                        hint: 'vpn.example.com',
                      ),
                      text(
                        'credential',
                        'UUID',
                        '填写服务端配置的 VLESS 用户 ID。',
                        secret: true,
                      ),
                      text(
                        'sni',
                        'SNI',
                        '填写 REALITY 服务端允许的 serverName。',
                        hint: 'www.example.org',
                      ),
                      text(
                        'publicKey',
                        'REALITY 公钥',
                        '填写服务端提供的 X25519 公钥（分享链接中的 pbk）。',
                      ),
                      text(
                        'shortId',
                        'shortId',
                        '服务端允许的十六进制 ID，最多 16 位，长度为偶数。服务端允许空值时可留空。',
                      ),
                      text('port', '服务器端口', '默认 443，请与服务端监听端口保持一致。'),
                      text('name', '节点名称', '此名称显示在节点列表中。'),
                    ] else ...[
                      Text(
                        '每个参数旁的 ? 支持鼠标悬浮或点击查看说明。',
                        style: TextStyle(
                          color: Calm.of(context).muted,
                          fontSize: 12,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('参数表单')),
                              ButtonSegment(
                                value: true,
                                label: Text('完整出站 JSON'),
                              ),
                            ],
                            selected: {rawMode},
                            onSelectionChanged: saving
                                ? null
                                : (set) => _switchEditor(set.first),
                          ),
                          const HelpIcon(
                            '完整 JSON 支持当前内核的全部出站字段与传输参数。只编辑单个出站对象，客户端管理入站和路由；外部脚本、文件引用和出站链仍受校验限制。',
                          ),
                        ],
                      ),
                      if (rawMode) ...[
                        const SizedBox(height: 16),
                        text(
                          'name',
                          '节点名称',
                          '此名称用于客户端列表；JSON 中的 tag 在生成运行配置时统一为 proxy。',
                        ),
                        TextField(
                          controller: raw,
                          enabled: !saving,
                          minLines: 16,
                          maxLines: 24,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                          decoration: helpDecoration(
                            '完整出站 JSON',
                            '填写包含 protocol、settings、streamSettings 等字段的单个 Xray 出站对象；保存前会通过真实内核校验。',
                          ),
                        ),
                      ] else ...[
                        section('基础信息'),
                        text('name', '节点名称', '仅用于在客户端辨认节点，不会发送给服务器。'),
                        select(
                          'protocol',
                          '协议',
                          '选择服务器部署的协议，客户端与服务端必须一致。包含本地 Xray-core 的全部 13 种客户端出站；xdrive 位于 VLESS 的传输选项中。',
                          ManualProfile.protocols,
                          changed: (v) {
                            fields['credential']!.clear();
                            fields['flow']!.clear();
                            fields['mux']!.text = 'false';
                            fields['network']!.text =
                                ProtocolFields.defaultNetwork(v);
                            fields['security']!.text =
                                ProtocolFields.defaultSecurity(v);
                            for (final spec
                                in ProtocolFields.protocolFields[v] ??
                                    <ProtocolField>[]) {
                              fields[spec.id]!.text = spec.defaultValue;
                            }
                            for (final spec
                                in ProtocolFields.transportFields[value(
                                      'network',
                                    )] ??
                                    <ProtocolField>[]) {
                              fields[spec.id]!.text = spec.defaultValue;
                            }
                          },
                        ),
                        if (ProtocolCatalog.remote.contains(protocol))
                          text(
                            'address',
                            '服务器地址',
                            '填写域名、IPv4 或 IPv6 地址。不包含 https://、端口或路径。',
                            hint: 'server.example.com',
                          ),
                        if (ProtocolCatalog.remote.contains(protocol))
                          text(
                            'port',
                            '服务器端口',
                            '服务端监听的端口，范围为 1–65535；TLS 常用 443，但必须以服务端配置为准。',
                          ),
                        if (ProtocolCatalog.utility.contains(protocol))
                          Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: Text(
                              '这是 Xray 内置路由出站，不是通用远端代理。DNS 只处理 DNS，blackhole 会阻断流量。',
                              style: TextStyle(color: Calm.of(context).muted),
                            ),
                          ),
                        if (ManualProfile.basicProtocols.contains(
                          protocol,
                        )) ...[
                          section('身份认证'),
                          text(
                            'credential',
                            ['vless', 'vmess'].contains(protocol)
                                ? 'UUID / 用户 ID'
                                : '密码',
                            ['vless', 'vmess'].contains(protocol)
                                ? '客户端与服务端用户 ID 必须一致。生成的新 UUID 也需要配置到服务器后才能连接。'
                                : '必须与服务端密码完全一致；不会自动去掉密码首尾的空格。',
                            secret: true,
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: saving
                                    ? null
                                    : () => setState(() => reveal = !reveal),
                                icon: Icon(
                                  reveal
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                label: Text(reveal ? '隐藏凭据' : '显示凭据'),
                              ),
                              if (['vless', 'vmess'].contains(protocol))
                                TextButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () {
                                          final bytes = List.generate(
                                            16,
                                            (_) => Random.secure().nextInt(256),
                                          );
                                          bytes[6] = (bytes[6] & 15) | 64;
                                          bytes[8] = (bytes[8] & 63) | 128;
                                          final h = bytes
                                              .map(
                                                (b) => b
                                                    .toRadixString(16)
                                                    .padLeft(2, '0'),
                                              )
                                              .join();
                                          fields['credential']!.text =
                                              '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
                                        },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('生成 UUID'),
                                ),
                            ],
                          ),
                          if (protocol == 'vless') ...[
                            text(
                              'encryption',
                              'VLESS encryption',
                              '普通 VLESS 填 none。使用新式 VLESS 加密时，粘贴服务端提供的完整 encryption 参数。',
                            ),
                            select(
                              'flow',
                              'Flow',
                              '通常留空；Vision 选择 xtls-rprx-vision。Vision 需要 TCP/RAW + TLS/REALITY，不能搭配 Mux。',
                              [
                                '',
                                'xtls-rprx-vision',
                                'xtls-rprx-vision-udp443',
                              ],
                            ),
                          ],
                          if (protocol == 'vmess')
                            select(
                              'cipher',
                              'VMess 加密方式',
                              'VMess AEAD 数据加密算法；通常使用 auto。客户端不支持旧的非零 alterId 模式。',
                              [
                                'auto',
                                'aes-128-gcm',
                                'chacha20-poly1305',
                                'none',
                                'zero',
                              ],
                            ),
                          if (protocol == 'shadowsocks')
                            select(
                              'method',
                              'Shadowsocks 加密方式',
                              '必须与服务端 method 一致。列表是当前固定版本 Xray-core 支持的 AEAD 算法。',
                              ManualProfile.ciphers,
                            ),
                        ],
                        if ((ProtocolFields.protocolFields[protocol] ?? [])
                            .isNotEmpty)
                          section('协议参数'),
                        for (final spec
                            in ProtocolFields.protocolFields[protocol] ??
                                <ProtocolField>[])
                          parameter(spec),
                        if (!ProtocolCatalog.utility.contains(protocol) &&
                            protocol != 'wireguard') ...[
                          section('传输层'),
                          select(
                            'network',
                            '传输协议',
                            '选择服务端的传输方式。TCP 与 RAW 是同类名称；WebSocket、gRPC、XHTTP 和 HTTPUpgrade 需要匹配额外参数。',
                            ProtocolFields.allowedNetworks(protocol),
                            changed: (v) {
                              if (v == 'xdrive') {
                                fields['flow']!.clear();
                                fields['mux']!.text = 'true';
                                fields['concurrency']!.text = '128';
                              }
                            },
                          ),
                          if ([
                            'ws',
                            'xhttp',
                            'httpupgrade',
                          ].contains(network)) ...[
                            text(
                              'path',
                              '请求路径',
                              '传输请求路径，需要与服务端或反向代理匹配，通常以 / 开头。',
                            ),
                            text(
                              'host',
                              'HTTP Host',
                              'HTTP Host 请求头，可与连接地址不同。未配置时使用协议默认行为；它与 TLS 的 SNI 是两个独立参数。',
                            ),
                          ],
                          if (network == 'ws')
                            text(
                              'headers',
                              '附加请求头 JSON',
                              '可填写字符串键值对 JSON 对象，例如 {"User-Agent":"fcxray"}。Host 字段以独立的 HTTP Host 输入为准。',
                              lines: 3,
                            ),
                          if (network == 'grpc') ...[
                            text(
                              'serviceName',
                              'gRPC Service Name',
                              '服务名必须与服务端一致，不需要前导 /。',
                            ),
                            text(
                              'authority',
                              'gRPC Authority',
                              '覆盖 HTTP/2 :authority，通常可留空。它不会替代 TLS 的 SNI。',
                            ),
                            select(
                              'multiMode',
                              'gRPC Multi Mode',
                              '仅在服务端要求 gRPC multi 模式时启用；其余情况选择 false。',
                              ['false', 'true'],
                            ),
                          ],
                          if (network == 'xhttp') ...[
                            select(
                              'xhttpMode',
                              'XHTTP 模式',
                              '通常选择 auto，由内核选择收发方式；指定模式必须与服务端部署兼容。',
                              ['auto', 'packet-up', 'stream-up', 'stream-one'],
                            ),
                            text(
                              'extra',
                              'XHTTP extra JSON',
                              '可选 XHTTP 高级参数对象；保留服务端提供的键值。保存时由 Xray-core 校验，不支持外部脚本和文件引用。',
                              lines: 4,
                            ),
                          ],
                          for (final spec
                              in ProtocolFields.transportFields[network] ??
                                  <ProtocolField>[])
                            if (!(spec.id == 'xdS3' &&
                                    value('xdService') != 's3') &&
                                !(spec.id == 'xdTemplate' &&
                                    value('xdService') != 'template') &&
                                !(spec.id == 'xdSecrets' &&
                                    value('xdService') == 'local'))
                              parameter(spec),
                          section('传输安全'),
                          select(
                            'security',
                            '传输安全',
                            'TLS 校验服务器证书；REALITY 使用服务端公钥和指定 SNI。none 不提供这一层加密。',
                            ['hysteria', 'masque'].contains(protocol)
                                ? ['tls']
                                : network == 'xdrive'
                                ? ['none', 'tls']
                                : ['none', 'tls', 'reality'],
                          ),
                          if (security != 'none') ...[
                            text(
                              'sni',
                              '服务器名称 / SNI',
                              security == 'reality'
                                  ? '填写 REALITY 服务端允许的 serverName，必填。'
                                  : '证书对应的域名；IP 连接时通常需要填写。为空时由内核使用默认服务器名称。',
                            ),
                            text(
                              'fingerprint',
                              'TLS 指纹',
                              'uTLS ClientHello 指纹，例如 chrome、firefox、safari 或 randomized；通常使用 chrome。',
                            ),
                          ],
                          if (security == 'tls')
                            text(
                              'alpn',
                              'ALPN',
                              '可选，使用逗号分隔，如 h2,http/1.1。留空由内核和传输方式决定。',
                            ),
                          if (security == 'reality') ...[
                            text(
                              'publicKey',
                              'REALITY 公钥',
                              '服务端提供的 X25519 公钥，也可能在新版本中称为 password；不要填写服务端私钥。',
                            ),
                            text(
                              'shortId',
                              'REALITY Short ID',
                              '服务端允许的十六进制 shortId，通常为 0–16 个字符且长度为偶数。',
                            ),
                            text(
                              'spiderX',
                              'REALITY Spider X',
                              '可选爬虫路径，通常保留 /。',
                            ),
                            text(
                              'mldsa65Verify',
                              'ML-DSA-65 验证公钥',
                              '可选；只有服务端启用相应后量子签名时才填写提供的验证公钥。',
                            ),
                          ],
                        ],
                        if (ManualProfile.basicProtocols.contains(
                          protocol,
                        )) ...[
                          section('多路复用'),
                          select(
                            'mux',
                            '启用 Mux',
                            '复用传输连接，是否有帮助取决于协议和服务端。默认关闭；Vision 不能启用。',
                            ['false', 'true'],
                          ),
                          if (value('mux') == 'true')
                            text(
                              'concurrency',
                              'Mux 并发数',
                              '每个复用连接承载的并发数。默认 8；允许 1–1024，具体模式仍由内核检查。',
                            ),
                        ],
                        section('高级传输参数'),
                        for (final spec in ProtocolFields.common)
                          parameter(spec),
                      ],
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Text(
                  error!,
                  style: TextStyle(color: Calm.of(context).error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: saving ? null : _save,
                    icon: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(saving ? '正在校验…' : '校验并保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget parameter(ProtocolField spec) {
    if (spec.kind == 'bool' || spec.choices.isNotEmpty) {
      return select(
        spec.id,
        spec.label,
        spec.help,
        spec.kind == 'bool' ? ['false', 'true'] : spec.choices,
        changed: (value) {
          if (spec.id == 'xdService') {
            fields['security']!.text = value == 'local' ? 'none' : 'tls';
          }
        },
      );
    }
    return text(
      spec.id,
      spec.label,
      spec.help,
      secret: ['secret', 'secrets'].contains(spec.kind),
      lines: ['object', 'array'].contains(spec.kind) ? 4 : 1,
    );
  }

  Profile _parseRaw() {
    final decoded = jsonDecode(raw.text);
    if (decoded is! Map<String, dynamic> || decoded['protocol'] is! String) {
      throw const FormatException('请填写单个出站 JSON 对象');
    }
    final p = ProfileImporter.parse(raw.text).single;
    return Profile(
      id: p.id,
      name: value('name').trim().isEmpty ? p.name : value('name').trim(),
      outbound: p.outbound,
    );
  }

  void _switchEditor(bool next) {
    if (next == rawMode) return;
    try {
      if (next) {
        try {
          raw.text = const JsonEncoder.withIndent('  ').convert(
            ManualProfile.build(
              fields.map((k, c) => MapEntry(k, c.text)),
              original: baseProfile,
            ).outbound,
          );
        } on Object {
          raw.text = const JsonEncoder.withIndent('  ').convert(
            baseProfile?.outbound ??
                {
                  'protocol': value('protocol'),
                  'settings': <String, dynamic>{},
                  'streamSettings': {
                    'network': value('network'),
                    'security': value('security'),
                  },
                },
          );
        }
        rawAtOpen = raw.text;
      } else if (raw.text != rawAtOpen) {
        final profile = _parseRaw();
        baseProfile = profile;
        for (final entry in ManualProfile.fields(profile).entries) {
          fields[entry.key]!.text = entry.value;
        }
      }
      setState(() {
        rawMode = next;
        error = null;
      });
    } on Object catch (e) {
      setState(() => error = e is FormatException ? e.message : 'JSON 格式无效');
    }
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final profile = rawMode
          ? _parseRaw()
          : ManualProfile.build(
              fields.map((k, c) => MapEntry(k, c.text)),
              original: baseProfile,
            );
      await widget.controller.saveManual(
        profile,
        replacingId: widget.original?.subscriptionId == null
            ? widget.original?.id
            : null,
      );
      if (mounted) Navigator.pop(context);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is FormatException ? e.message : '保存或内核校验失败：$e';
        });
      }
    }
  }
}
