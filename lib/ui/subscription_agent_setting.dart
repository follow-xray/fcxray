import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../models/resources.dart';
import 'calm_theme.dart';
import 'help_fields.dart';

class SubscriptionAgentSetting extends StatelessWidget {
  const SubscriptionAgentSetting(this.controller, {super.key});
  final AppController controller;

  Future<void> _edit(BuildContext context) async {
    var mode = controller.subscriptionAgent;
    var custom = controller.customSubscriptionAgent;
    String? error;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, update) => AlertDialog(
          title: const Text('订阅 User-Agent'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HelpDropdown<SubscriptionAgent>(
                  label: '客户端标识',
                  help: '订阅服务器可能根据此请求头返回不同格式。',
                  value: mode,
                  items: [
                    for (final item in SubscriptionAgent.values)
                      DropdownMenuItem(value: item, child: Text(item.label)),
                  ],
                  onChanged: (next) => update(() {
                    mode = next!;
                    error = null;
                  }),
                ),
                const SizedBox(height: 12),
                if (mode == SubscriptionAgent.custom)
                  TextFormField(
                    initialValue: custom,
                    decoration: helpDecoration(
                      '自定义 User-Agent',
                      '输入要发送的完整请求头值，例如 MyClient/1.0。',
                    ).copyWith(errorText: error),
                    onChanged: (value) {
                      custom = value;
                      if (error != null) update(() => error = null);
                    },
                  )
                else
                  SelectableText(mode.header(controller.platform, custom)),
                if (mode == SubscriptionAgent.clash) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '部分订阅源会返回 Clash YAML，当前支持分享链接、Base64 和 Xray 出站 JSON。',
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (mode == SubscriptionAgent.custom &&
                    !SubscriptionAgent.validCustom(custom)) {
                  update(() => error = '请输入非空的单行 ASCII User-Agent');
                  return;
                }
                Navigator.pop(dialog, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (save != true || !context.mounted) return;
    try {
      await controller.setSubscriptionAgent(mode, custom);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('订阅 User-Agent 保存失败，请重试。')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => SoftSurface(
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('订阅 User-Agent'),
      subtitle: Text(
        '${controller.subscriptionAgent.label} · ${controller.subscriptionHeader}',
      ),
      trailing: const Icon(Icons.edit_outlined),
      onTap: controller.resourcesEditable ? () => _edit(context) : null,
    ),
  );
}
