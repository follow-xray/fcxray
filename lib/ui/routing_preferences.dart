import 'calm_theme.dart';
import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../models/route_override.dart';
import '../services/config_builder.dart';
import 'help_fields.dart';
import '../services/rule_exchange.dart';

class RoutingPreferences extends StatelessWidget {
  const RoutingPreferences(this.controller, {super.key});
  final AppController controller;

  Future<void> _edit(BuildContext context, [RouteOverride? existing]) =>
      showDialog<void>(
        context: context,
        builder: (_) => _RuleEditor(controller, existing),
      );
  Future<void> _save(BuildContext context, List<RouteOverride> rules) async {
    try {
      await controller.saveOverrides(rules);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '规则模式选项',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('绕过局域网'),
          subtitle: const Text('在规则模式下，将私网地址直连。'),
          value: c.bypassLan,
          onChanged: c.resourcesEditable
              ? (v) => _option(context, lan: v)
              : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('GeoIP / GeoSite 分流'),
          subtitle: const Text('在“路由与规则”管理规则库和分类。'),
          value: c.useGeo,
          onChanged: c.resourcesEditable
              ? (v) => _option(context, geo: v)
              : null,
        ),
        const Divider(),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              '自定义规则',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('添加规则'),
              onPressed: c.resourcesEditable ? () => _edit(context) : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('导入 JSON'),
              onPressed: c.resourcesEditable ? () => _import(context) : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('导出 JSON'),
              onPressed: c.loaded ? () => _export(context) : null,
            ),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('立即应用'),
              onPressed:
                  c.connected &&
                      c.resourcesEditable &&
                      c.routing == RoutingMode.rules
                  ? () => _apply(context)
                  : null,
            ),
          ],
        ),
        Text(
          '规则模式下，首个匹配项优先于局域网和 Geo 分类。连接中点“立即应用”后，新请求使用新规则。',
          style: TextStyle(color: Calm.of(context).muted),
        ),
        for (final (i, rule) in c.overrides.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Checkbox(
              value: rule.enabled,
              onChanged: c.resourcesEditable
                  ? (_) => _save(context, [...c.overrides]..[i] = rule.toggle())
                  : null,
            ),
            title: Text(rule.target, overflow: TextOverflow.ellipsis),
            subtitle: Text('${rule.kind.label} · ${rule.action.label}'),
            onTap: c.resourcesEditable ? () => _edit(context, rule) : null,
            trailing: PopupMenuButton<String>(
              enabled: c.resourcesEditable,
              tooltip: '规则操作',
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(
                  value: 'up',
                  enabled: i > 0,
                  child: const Text('上移'),
                ),
                PopupMenuItem(
                  value: 'down',
                  enabled: i + 1 < c.overrides.length,
                  child: const Text('下移'),
                ),
                const PopupMenuItem(value: 'remove', child: Text('删除')),
              ],
              onSelected: (action) {
                if (action == 'edit') {
                  _edit(context, rule);
                  return;
                }
                final rules = [...c.overrides];
                final index = rules.indexOf(rule);
                if (index < 0) return;
                rules.removeAt(index);
                if (action != 'remove') {
                  rules.insert(
                    (index + (action == 'up' ? -1 : 1)).clamp(0, rules.length),
                    rule,
                  );
                }
                _save(context, rules);
              },
            ),
          ),
      ],
    );
  }

  void _message(BuildContext context, String text) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _apply(BuildContext context) async {
    try {
      await controller.applyRulesNow();
      if (context.mounted) _message(context, '已应用，新请求将使用当前规则。');
    } catch (e) {
      if (context.mounted) _message(context, '应用失败：$e');
    }
  }

  Future<void> _export(BuildContext context) async {
    try {
      if (await RuleExchange.save(controller.overrides) && context.mounted) {
        _message(context, '自定义规则已导出');
      }
    } catch (e) {
      if (context.mounted) _message(context, '导出失败：$e');
    }
  }

  Future<void> _import(BuildContext context) async {
    try {
      final rules = await RuleExchange.pick();
      if (rules == null || !context.mounted) return;
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入自定义规则'),
          content: Text(
            '文件包含 ${rules.length} 条规则，现有 ${controller.overrides.length} 条。替换会使用文件中的顺序和启停状态。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: rules.isEmpty ? null : () => Navigator.pop(ctx, false),
              child: const Text('追加到末尾'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('替换现有规则'),
            ),
          ],
        ),
      );
      if (replace == null) return;
      await controller.saveOverrides(
        replace ? rules : [...controller.overrides, ...rules],
      );
      if (context.mounted) {
        _message(context, controller.connected ? '导入完成，可点击“立即应用”。' : '规则已导入');
      }
    } catch (e) {
      if (context.mounted) _message(context, '导入失败：$e');
    }
  }

  Future<void> _option(BuildContext context, {bool? lan, bool? geo}) async {
    try {
      await controller.ruleOptions(lan: lan, geo: geo);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }
}

class _RuleEditor extends StatefulWidget {
  const _RuleEditor(this.controller, this.original);
  final AppController controller;
  final RouteOverride? original;
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final input = TextEditingController(text: widget.original?.target ?? '');
  late TargetKind kind = widget.original?.kind ?? TargetKind.domain;
  late RouteAction action = widget.original?.action ?? RouteAction.direct;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.original == null ? '添加路由规则' : '编辑路由规则'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HelpDropdown<TargetKind>(
              label: '匹配方式',
              help:
                  '域名及子域名可匹配 example.com 和 www.example.com。精确域名只匹配完整名称。IP 支持 IPv4、IPv6 和 CIDR。',
              value: kind,
              items: [
                for (final k in TargetKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: saving ? null : (v) => setState(() => kind = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: input,
              minLines: widget.original == null ? 3 : 1,
              maxLines: widget.original == null ? 6 : 1,
              autocorrect: false,
              enableSuggestions: false,
              decoration: helpDecoration(
                widget.original == null ? '匹配目标（每行一个）' : '匹配目标',
                '仅输入主机名或 IP/网段。同一匹配方式和目标只能添加一次。',
                hint: kind == TargetKind.ip
                    ? '192.168.1.10\n10.8.0.0/16'
                    : 'example.com',
              ),
            ),
            const SizedBox(height: 16),
            HelpDropdown<RouteAction>(
              label: '流量去向',
              help: '直连使用系统网络，代理使用所选节点，拒绝会丢弃匹配流量。',
              value: action,
              items: [
                for (final a in RouteAction.values)
                  DropdownMenuItem(value: a, child: Text(a.label)),
              ],
              onChanged: saving ? null : (v) => setState(() => action = v!),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: saving ? null : _submit, child: const Text('保存')),
    ],
  );
  Future<void> _submit() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final values = input.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty);
      if (values.isEmpty) throw const FormatException('请填写匹配目标');
      final additions = values
          .map(
            (s) => RouteOverride.parse(
              kind,
              s,
              action,
              enabled: widget.original?.enabled ?? true,
            ),
          )
          .toList();
      final next = [...widget.controller.overrides];
      final original = widget.original;
      if (original == null) {
        next.addAll(additions);
      } else {
        final index = next.indexWhere((r) => r.key == original.key);
        if (index < 0) throw const FormatException('原规则已删除，请重新添加');
        next[index] = additions.single;
      }
      await widget.controller.saveOverrides(next);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is FormatException ? e.message : '保存失败：$e';
        });
      }
    }
  }
}
