import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../services/config_backup.dart';
import '../services/json_document.dart';
import 'calm_theme.dart';

class BackupActions extends StatefulWidget {
  const BackupActions(
    this.controller, {
    this.recovery = false,
    this.allowExport = true,
    super.key,
  });
  final AppController controller;
  final bool recovery, allowExport;
  @override
  State<BackupActions> createState() => _BackupActionsState();
}

class _BackupActionsState extends State<BackupActions> {
  bool working = false;
  String? message;
  AppController get c => widget.controller;

  Future<bool> _confirm(String title, String detail, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _run(Future<void> Function() action) async {
    if (working) return;
    setState(() {
      working = true;
      message = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => message = e is SecretBoxAuthenticationError
              ? '密码错误或备份已损坏'
              : e is FormatException
              ? (e.message.toString().contains('32 MiB')
                    ? '备份文件超过 32 MiB'
                    : '备份无效或已损坏')
              : '操作失败，请检查文件或存储权限后重试',
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<String?> _password({required bool creating}) {
    var password = '', repeat = '';
    String? error;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, update) => AlertDialog(
          title: Text(creating ? '设置备份密码' : '输入备份密码'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: '备份密码'),
                  onChanged: (value) => password = value,
                ),
                if (creating)
                  TextField(
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: '再次输入密码'),
                    onChanged: (value) => repeat = value,
                  ),
                if (error != null) Text(error!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (password.isEmpty || (creating && password != repeat)) {
                  update(() => error = password.isEmpty ? '请输入密码' : '两次密码不一致');
                } else {
                  Navigator.pop(ctx, password);
                }
              },
              child: Text(creating ? '继续导出' : '解密'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export() async {
    final password = await _password(creating: true);
    if (password == null || !mounted) return;
    final bytes = await encryptBackup(c.exportBackup(), password);
    if (!mounted) return;
    final saved = await JsonDocument.backup.save(bytes);
    if (saved && mounted) setState(() => message = '备份已导出');
  }

  Future<void> _restore(ConfigBackup backup) async {
    final time = backup.savedAt.toLocal().toString().substring(0, 16);
    final count = (backup.state['profiles'] as List).length;
    if (!await _confirm(
          '恢复这份配置？',
          '$time · $count 个节点\n将替换节点、订阅和偏好设置。',
          '恢复',
        ) ||
        !mounted) {
      return;
    }
    await c.restoreBackup(backup);
    if (mounted) setState(() => message = '配置已恢复');
  }

  Future<void> _import() async {
    final bytes = await JsonDocument.backup.pick();
    if (bytes == null || !mounted) return;
    final password = await _password(creating: false);
    if (password == null || !mounted) return;
    final backup = await decryptBackup(bytes, password);
    if (mounted) await _restore(backup);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !working && !c.saving && !c.initializing && !c.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (c.localBackup case final backup?)
              FilledButton.tonalIcon(
                onPressed: enabled ? () => _run(() => _restore(backup)) : null,
                icon: const Icon(Icons.restore),
                label: const Text('恢复自动备份'),
              ),
            OutlinedButton.icon(
              onPressed: enabled ? () => _run(_import) : null,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('从文件恢复'),
            ),
            if (!widget.recovery && widget.allowExport)
              OutlinedButton.icon(
                onPressed: enabled ? () => _run(_export) : null,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('导出备份'),
              ),
            if (widget.recovery) ...[
              TextButton(
                onPressed: enabled ? () => c.initialize() : null,
                child: const Text('重新读取'),
              ),
              TextButton(
                onPressed: enabled
                    ? () => _run(() async {
                        if (await _confirm('使用空配置？', '原文件会保留到下次保存设置。', '继续') &&
                            mounted) {
                          await c.restoreBackup(null);
                        }
                      })
                    : null,
                child: const Text('使用空配置'),
              ),
            ],
          ],
        ),
        if ((working || c.saving) && (ModalRoute.isCurrentOf(context) ?? true))
          const LinearProgressIndicator(),
        if (message ?? c.backupError case final text?) Text(text),
      ],
    );
  }
}

class StartupPanel extends StatelessWidget {
  const StartupPanel(this.controller, {super.key});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SoftSurface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'fcxray',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28),
                  ),
                  const SizedBox(height: 18),
                  if (controller.error case final error?) ...[
                    Text(error),
                    const SizedBox(height: 16),
                    BackupActions(controller, recovery: true),
                  ] else ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    const Text('正在读取配置…'),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
