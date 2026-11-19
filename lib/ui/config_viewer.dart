import 'calm_theme.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/app_controller.dart';
import 'help_fields.dart';

Object? redactConfig(Object? value, [String key = '']) {
  const secretKeys = {
    'id',
    'password',
    'pass',
    'privatekey',
    'encryption',
    'mldsa65seed',
    'authorization',
    'cookie',
    'secretkey',
    'presharedkey',
    'secrets',
    'auth',
    'token',
    'clientsecret',
    'refreshtoken',
    'accesskeyid',
    'secretaccesskey',
    'sessiontoken',
    'seed',
  };
  if (secretKeys.contains(key.toLowerCase()) &&
      value != null &&
      value != 'none' &&
      value != '') {
    return '••••••';
  }
  if (key.toLowerCase() == 'headers' && value is Map) {
    return value.map((k, v) => MapEntry('$k', '••••••'));
  }
  if (value is Map) {
    return value.map((k, v) => MapEntry('$k', redactConfig(v, '$k')));
  }
  if (value is List) return value.map((v) => redactConfig(v)).toList();
  return value;
}

Future<void> showConfigViewer(BuildContext context, AppController controller) =>
    showDialog<void>(
      context: context,
      builder: (_) => ConfigViewer(controller: controller),
    );

class ConfigViewer extends StatefulWidget {
  const ConfigViewer({super.key, required this.controller});
  final AppController controller;
  @override
  State<ConfigViewer> createState() => _ConfigViewerState();
}

class _ConfigViewerState extends State<ConfigViewer> {
  Map<String, dynamic>? snapshot;
  String? error;
  bool loading = true, reveal = false, preview = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await (preview
          ? widget.controller.previewConfiguration()
          : widget.controller.configuration());
      if (mounted) setState(() => snapshot = data);
    } on Object catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String get content {
    if (snapshot == null) return '';
    final decoded = jsonDecode(snapshot!['config'] as String);
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(reveal ? decoded : redactConfig(decoded));
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 980,
      height: min(MediaQuery.sizeOf(context).height * .9, 860),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '配置文件',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: '刷新配置',
                  onPressed: loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('当前连接')),
                    ButtonSegment(value: true, label: Text('下次连接')),
                  ],
                  selected: {preview},
                  onSelectionChanged: loading
                      ? null
                      : (values) {
                          setState(() => preview = values.first);
                          _load();
                        },
                ),
                const SizedBox(height: 12),
                Text(
                  snapshot?['source'] as String? ?? '正在读取…',
                  style: TextStyle(color: Calm.of(context).iris),
                ),
                const SizedBox(height: 8),
                Text(
                  '运行中显示内核当前使用的 JSON；“下次连接”显示已更新但尚未应用的预览。当前连接不因订阅或规则更新而重启；配置只保存在内存中。',
                  style: TextStyle(color: Calm.of(context).muted, fontSize: 12),
                ),
                if ((snapshot?['assetDirectory'] as String? ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SelectableText(
                      '规则库目录：${snapshot!['assetDirectory']}',
                      style: TextStyle(
                        color: Calm.of(context).muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Switch(
                      value: reveal,
                      onChanged: loading
                          ? null
                          : (v) => setState(() => reveal = v),
                    ),
                    const Text('显示完整凭据'),
                    const HelpIcon(
                      '默认隐藏 UUID、密码等字段；打开后可查看内核接收到的原始凭据。复制按钮会复制当前显示的内容。',
                    ),
                    TextButton.icon(
                      onPressed: loading || snapshot == null
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: content),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      reveal ? '已复制完整配置' : '已复制脱敏配置',
                                    ),
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.copy),
                      label: Text(reveal ? '复制完整 JSON' : '复制脱敏 JSON'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SelectableText(error!),
                    ),
                  )
                : ColoredBox(
                    color: Calm.of(context).inset,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(22),
                      child: SelectableText(
                        content,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
