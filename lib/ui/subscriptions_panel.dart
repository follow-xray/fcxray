import 'calm_theme.dart';
import 'format_bytes.dart';
import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../models/resources.dart';
import 'help_fields.dart';

String dateLabel(DateTime? value) =>
    value == null ? '从未更新' : value.toLocal().toString().substring(0, 19);
List<DropdownMenuItem<int>> updateIntervals() => [0, 6, 12, 24, 72, 168]
    .map(
      (h) =>
          DropdownMenuItem(value: h, child: Text(h == 0 ? '仅手动更新' : '每 $h 小时')),
    )
    .toList();
void showOperationError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error is FormatException ? error.message : '操作失败：$error'),
    ),
  );
}

class SubscriptionsPanel extends StatelessWidget {
  const SubscriptionsPanel({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: c.resourcesEditable
                        ? () => _edit(context)
                        : null,
                    icon: const Icon(Icons.add_link),
                    label: const Text('添加订阅 / 批量导入'),
                  ),
                  OutlinedButton.icon(
                    onPressed: c.resourcesEditable && c.subscriptions.isNotEmpty
                        ? () async {
                            try {
                              await c.updateSubscriptions();
                            } on Object catch (e) {
                              if (context.mounted) {
                                showOperationError(context, e);
                              }
                            }
                          }
                        : null,
                    icon: const Icon(Icons.sync),
                    label: const Text('更新全部'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '支持多个 HTTPS 订阅；分享链接列表、Base64 内容、Xray 出站 JSON 均可。VPN 连接时也可更新，优先通过当前代理下载，失败重试系统网络。新节点下次连接生效，关闭应用后不执行定时更新。',
                style: TextStyle(color: Calm.of(context).muted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (c.subscriptions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text('还没有订阅。可以一次粘贴多个地址，每行一个。'),
            ),
          ),
        for (final s in c.subscriptions)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TintIcon(
                          Icons.rss_feed,
                          fill: Calm.of(context).peach,
                          ink: Calm.of(context).clay,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            s.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '编辑订阅',
                          onPressed: c.resourcesEditable
                              ? () => _edit(context, s)
                              : null,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${Uri.tryParse(s.url)?.host ?? '订阅'} · ${c.profiles.where((p) => p.subscriptionId == s.id).length} 个节点',
                      style: TextStyle(color: Calm.of(context).muted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '上次成功：${dateLabel(s.updatedAt)}\n更新周期：${s.autoHours == 0 ? '手动' : '${s.autoHours} 小时'}',
                      style: TextStyle(
                        color: Calm.of(context).muted,
                        fontSize: 12,
                      ),
                    ),
                    if (s.usage case final usage?)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          [
                            if (usage.upload != null)
                              '已上传 ${formatBytes(usage.upload!)}',
                            if (usage.download != null)
                              '已下载 ${formatBytes(usage.download!)}',
                            if (usage.total != null && usage.total! > 0)
                              '总配额 ${formatBytes(usage.total!)}',
                            if (usage.expire != null)
                              '到期 ${dateLabel(DateTime.fromMillisecondsSinceEpoch(usage.expire! * 1000))}',
                          ].join(' · '),
                        ),
                      ),
                    if (s.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          s.error!,
                          style: TextStyle(
                            color: Calm.of(context).error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: c.resourcesEditable
                              ? () async {
                                  try {
                                    await c.updateSubscription(s.id);
                                  } on Object catch (e) {
                                    if (context.mounted) {
                                      showOperationError(context, e);
                                    }
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.refresh),
                          label: const Text('立即更新'),
                        ),
                        TextButton.icon(
                          onPressed: c.resourcesEditable
                              ? () => _delete(context, s)
                              : null,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('删除订阅'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, [Subscription? original]) async {
    final name = TextEditingController(text: original?.name ?? '');
    final urls = TextEditingController(text: original?.url ?? '');
    var hours = original?.autoHours ?? 24;
    var busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(original == null ? '添加订阅' : '编辑订阅'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    enabled: !busy,
                    decoration: helpDecoration(
                      '订阅名称',
                      '用于分组显示。批量添加时会自动附加序号；留空使用订阅服务器的域名。',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: urls,
                    enabled: !busy,
                    minLines: original == null ? 4 : 2,
                    maxLines: 6,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: helpDecoration(
                      original == null ? '订阅地址（每行一个）' : '订阅地址',
                      '仅支持 HTTPS。地址中的令牌保存在系统安全存储，卡片只展示域名。更改地址后需要更新才能替换节点。',
                      hint: 'https://example.com/subscription',
                    ),
                  ),
                  const SizedBox(height: 16),
                  HelpDropdown<int>(
                    label: '自动更新周期',
                    help: '应用运行时每分钟检查，连接中也可下载；当前连接不会重启，更新下次连接生效。失败后按周期重试。',
                    value: hours,
                    items: updateIntervals(),
                    onChanged: busy ? null : (v) => setState(() => hours = v!),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(color: Calm.of(context).error),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        if (original == null) {
                          final ids = await controller.addSubscriptions(
                            name.text,
                            urls.text,
                            hours,
                          );
                          await controller.updateSubscriptions(ids);
                        } else {
                          await controller.editSubscription(
                            Subscription(
                              id: original.id,
                              name: name.text.trim().isEmpty
                                  ? original.name
                                  : name.text.trim(),
                              url: urls.text.trim(),
                              autoHours: hours,
                              updatedAt: original.updatedAt,
                              attemptedAt: original.attemptedAt,
                              error: original.error,
                            ),
                          );
                        }
                        if (context.mounted) Navigator.pop(context);
                      } on Object catch (e) {
                        if (context.mounted) {
                          setState(() {
                            busy = false;
                            error = e is FormatException
                                ? e.message
                                : '保存失败，请检查安全存储或连接状态。';
                          });
                        }
                      }
                    },
              child: Text(
                busy
                    ? '正在处理…'
                    : original == null
                    ? '保存并更新'
                    : '保存',
              ),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    urls.dispose();
  }

  Future<void> _delete(BuildContext context, Subscription s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除订阅'),
        content: Text('删除“${s.name}”及其节点？其他订阅和手动节点不会受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        await controller.removeSubscription(s.id);
      } on Object catch (e) {
        if (context.mounted) showOperationError(context, e);
      }
    }
  }
}
