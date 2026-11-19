import 'calm_theme.dart';
import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../models/profile.dart';
import 'help_fields.dart';
import 'node_editor.dart';
import 'package:flutter/services.dart';
import '../services/profile_importer.dart';

class NodesPanel extends StatefulWidget {
  const NodesPanel({
    super.key,
    required this.controller,
    required this.onImport,
  });
  final AppController controller;
  final VoidCallback onImport;
  @override
  State<NodesPanel> createState() => _NodesPanelState();
}

class _NodesPanelState extends State<NodesPanel> {
  String query = '', source = 'all';
  int count = 100;
  bool sortByLatency = false;
  AppController get c => widget.controller;
  @override
  Widget build(BuildContext context) {
    final sources = {
      'all': '全部来源',
      'manual': '手动节点',
      for (final s in c.subscriptions) s.id: s.name,
    };
    final selectedSource = sources.containsKey(source) ? source : 'all';
    final filtered = c.profiles
        .where(
          (p) =>
              (selectedSource == 'all' ||
                  (selectedSource == 'manual'
                      ? p.subscriptionId == null
                      : p.subscriptionId == selectedSource)) &&
              '${p.name} ${p.host} ${p.protocol}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    final latency = c.latency;
    final nodes = sortByLatency ? latency.sorted(filtered) : filtered;
    final testable = filtered.where((p) => !p.isUtility);
    final active = c.activeProfile;
    final activeFingerprint = active == null
        ? null
        : AppController.fingerprint(active);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: c.editable ? () => showNodeEditor(context, c) : null,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('手动添加'),
            ),
            OutlinedButton.icon(
              onPressed: c.editable ? widget.onImport : null,
              icon: const Icon(Icons.input),
              label: const Text('导入节点'),
            ),
            OutlinedButton.icon(
              onPressed: _openExample,
              icon: const Icon(Icons.description_outlined),
              label: const Text('示例配置'),
            ),
            Text(
              '${c.profiles.length} 个节点',
              style: TextStyle(color: Calm.of(context).muted),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SoftSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                onChanged: (v) => setState(() {
                  query = v;
                  count = 100;
                }),
                decoration: helpDecoration('搜索节点', '按名称、服务器地址或协议筛选；不会发起网络探测。'),
              ),
              const SizedBox(height: 14),
              HelpDropdown<String>(
                label: '节点来源',
                help: '按手动节点或某个订阅分组。订阅更新只替换自己的节点，不影响其他来源。',
                value: selectedSource,
                items: sources.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  source = v!;
                  count = 100;
                }),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: latency.busy || testable.isEmpty
                        ? null
                        : () => latency.run(testable),
                    icon: const Icon(Icons.speed),
                    label: Text('批量测速（${testable.length}）'),
                  ),
                  FilterChip(
                    selected: sortByLatency,
                    label: const Text('按延迟排序'),
                    onSelected: (v) => setState(() => sortByLatency = v),
                  ),
                  const HelpIcon(
                    '通过每个候选节点请求 gstatic 的 HTTPS 204 响应，时间包含握手与首个响应。批量测试覆盖当前筛选的全部远端节点。',
                  ),
                  if (latency.busy)
                    TextButton(
                      onPressed: latency.stopping ? null : latency.stopQueue,
                      child: Text(
                        '${latency.stopping ? "收尾中" : "停止排队"} ${latency.completed}/${latency.total}',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (!c.editable)
          Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              '连接或更新期间不可编辑节点。',
              style: TextStyle(color: Calm.of(context).muted),
            ),
          ),
        if (nodes.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text('还没有匹配的节点。可以手动添加、粘贴导入或添加订阅。'),
            ),
          ),
        for (final p in nodes.take(count))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              color: c.selectedId == p.id
                  ? Calm.of(context).lilac
                  : Calm.of(context).paper,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: c.selectedId == p.id
                      ? Calm.of(context).iris
                      : Calm.of(context).line,
                ),
              ),
              child: ListTile(
                onTap: c.editable ? () => c.select(p.id) : null,
                leading: Icon(
                  c.selectedId == p.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: Calm.of(context).iris,
                ),
                title: Text(p.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${p.protocol.toUpperCase()} · ${p.endpointLabel}\n${latency.label(p)} · ${c.sourceName(p)}${p.id == active?.id && AppController.fingerprint(p) == activeFingerprint ? ' · 当前连接' : ''}',
                  style: TextStyle(fontSize: 12, color: Calm.of(context).muted),
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!p.isUtility)
                      IconButton(
                        tooltip: '测试此节点延迟',
                        icon: const Icon(Icons.speed),
                        onPressed: latency.busy ? null : () => latency.run([p]),
                      ),
                    PopupMenuButton<String>(
                      enabled: c.editable,
                      tooltip: '节点操作',
                      onSelected: (action) {
                        if (action == 'edit') {
                          showNodeEditor(context, c, p);
                        } else {
                          _remove(p);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(
                            p.subscriptionId == null ? '编辑参数' : '复制并编辑为手动节点',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除节点'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (nodes.length > count)
          TextButton(
            onPressed: () => setState(() => count += 100),
            child: Text('显示更多（当前 $count / ${nodes.length}）'),
          ),
      ],
    );
  }

  Future<void> _openExample() async {
    const base = 'assets/examples/vless-vision-tcp';
    final examples = await Future.wait([
      rootBundle.loadString('$base.json'),
      rootBundle.loadString('$base-reality.json'),
    ]);
    if (!mounted) return;
    var reality = false;
    final json = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          final content = examples[reality ? 1 : 0];
          return AlertDialog(
            title: const Text('VLESS + Vision + TCP'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('TLS')),
                      ButtonSegment(value: true, label: Text('REALITY')),
                    ],
                    selected: {reality},
                    onSelectionChanged: (v) => update(() => reality = v.single),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    reality
                        ? '使用服务端提供的地址、UUID、SNI、公钥和 shortId 创建节点。默认端口为 443。'
                        : '请替换服务器地址、UUID、端口和 TLS 证书对应的 SNI。',
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      key: ValueKey(reality),
                      child: SelectableText(
                        content,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: content));
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(
                      ctx,
                    ).showSnackBar(const SnackBar(content: Text('已复制示例 JSON')));
                  }
                },
                child: const Text('复制 JSON'),
              ),
              ListenableBuilder(
                listenable: c,
                builder: (_, _) => FilledButton(
                  onPressed: c.editable
                      ? () => Navigator.pop(ctx, content)
                      : null,
                  child: const Text('用示例新建节点'),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || json == null || !c.editable) return;
    final template = ProfileImporter.parse(json).single;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NodeEditor(controller: c, template: template),
    );
  }

  Future<void> _remove(Profile p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除节点'),
        content: Text(
          '删除“${p.name}”？${p.subscriptionId == null ? '' : '订阅节点在下次更新时可能重新出现。'}',
        ),
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
    if (yes == true) await c.remove(p.id);
  }
}
