import 'calm_theme.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/app_controller.dart';
import '../models/resources.dart';
import 'help_fields.dart';
import 'subscriptions_panel.dart';

class GeoPanel extends StatelessWidget {
  const GeoPanel({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftSurface(
          color: Calm.of(context).mint,
          child: Padding(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Row(
                    children: [
                      Expanded(child: Text('规则模式使用 GeoIP / GeoSite 分流')),
                      HelpIcon(
                        '优先级：TUN DNS 接管 → 自定义规则 → 局域网 → 阻止域名 → 直连域名 → 直连 IP → 其余代理。启用后对 HTTP/TLS/QUIC 开启仅用于路由的域名嗅探。',
                      ),
                    ],
                  ),
                  value: c.useGeo,
                  onChanged: c.resourcesEditable
                      ? (v) async {
                          try {
                            await c.ruleOptions(geo: v);
                          } catch (e) {
                            if (context.mounted) showOperationError(context, e);
                          }
                        }
                      : null,
                ),
                Text(
                  '直连 IP：${c.geoRouting.directIPs.join(', ')}\n直连域名：${c.geoRouting.directSites.join(', ')}\n阻止域名：${c.geoRouting.blockSites.isEmpty ? '未设置' : c.geoRouting.blockSites.join(', ')}',
                  style: TextStyle(color: Calm.of(context).muted, fontSize: 13),
                ),
                TextButton.icon(
                  onPressed: c.resourcesEditable
                      ? () => _routing(context)
                      : null,
                  icon: const Icon(Icons.tune),
                  label: const Text('编辑分类规则'),
                ),
                if (c.error != null)
                  Text(
                    c.error!,
                    style: TextStyle(
                      color: Calm.of(context).error,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        for (final asset in c.geoAssets.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TintIcon(
                          asset.kind == "geoip" ? Icons.public : Icons.language,
                          fill: asset.kind == "geoip"
                              ? Calm.of(context).mint
                              : Calm.of(context).lilac,
                          ink: asset.kind == "geoip"
                              ? Calm.of(context).pine
                              : Calm.of(context).iris,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            asset.kind == 'geoip'
                                ? 'GeoIP · IP 地址库'
                                : 'GeoSite · 域名库',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '设置更新来源',
                          onPressed: c.resourcesEditable
                              ? () => _source(context, asset)
                              : null,
                          icon: const Icon(Icons.settings_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      asset.installed
                          ? '${asset.tags.length} 个分类 · ${asset.entries} 条记录 · ${(asset.size / 1024 / 1024).toStringAsFixed(1)} MiB'
                          : '尚未安装',
                      style: TextStyle(color: Calm.of(context).muted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '上次成功：${dateLabel(asset.updatedAt)}\n自动更新：${asset.autoHours == 0 ? '关闭' : '每 ${asset.autoHours} 小时'}',
                      style: TextStyle(
                        color: Calm.of(context).muted,
                        fontSize: 12,
                      ),
                    ),
                    if (asset.installed)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SelectableText(
                          'SHA-256: ${asset.hash}',
                          style: TextStyle(
                            color: Calm.of(context).muted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    if (asset.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          asset.error!,
                          style: TextStyle(
                            color: Calm.of(context).error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: c.resourcesEditable
                              ? () => _import(context, asset.kind)
                              : null,
                          icon: const Icon(Icons.file_open_outlined),
                          label: const Text('导入 .dat'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: c.resourcesEditable
                              ? () async {
                                  try {
                                    await c.updateGeo(asset.kind);
                                  } on Object catch (e) {
                                    if (context.mounted) {
                                      showOperationError(context, e);
                                    }
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('立即更新'),
                        ),
                        TextButton(
                          onPressed: asset.installed
                              ? () => _tags(context, asset)
                              : null,
                          child: const Text('查看分类'),
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

  Future<void> _import(BuildContext context, String kind) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Xray geodata',
            extensions: ['dat'],
            mimeTypes: ['application/octet-stream'],
            uniformTypeIdentifiers: ['public.data'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 64 * 1024 * 1024) {
        throw const FormatException('规则库不能超过 64 MiB');
      }
      await controller.importGeo(kind, file.openRead());
    } on Object catch (e) {
      if (context.mounted) showOperationError(context, e);
    }
  }

  Future<void> _source(BuildContext context, GeoAsset asset) async {
    final url = TextEditingController(text: asset.url),
        hash = TextEditingController(text: asset.expectedHash);
    var hours = asset.autoHours;
    var busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('${asset.kind} 更新来源'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: url,
                    enabled: !busy,
                    maxLines: 3,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: helpDecoration(
                      '下载地址',
                      '填写原始 .dat 文件的 HTTPS 直链。默认来源是 Loyalsoldier/v2ray-rules-dat，可替换为你信任的兼容数据库。',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: hash,
                    enabled: !busy,
                    decoration: helpDecoration(
                      '预期 SHA-256（可选）',
                      '填写 64 位十六进制摘要时，只接受匹配的版本。留空仍执行 TLS 和 protobuf 格式校验；摘要不等于发布者签名。',
                    ),
                  ),
                  const SizedBox(height: 16),
                  HelpDropdown<int>(
                    label: '自动更新周期',
                    help:
                        '应用运行时执行，VPN 连接中优先通过当前代理下载；不重启连接，新库下次连接生效。固定摘要需随目标版本调整。',
                    value: hours,
                    items: updateIntervals(hours),
                    onChanged: busy ? null : (v) => setState(() => hours = v!),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(color: Calm.of(context).error),
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
                      setState(() => busy = true);
                      try {
                        await controller.configureGeo(
                          asset.withSettings(
                            url.text.trim(),
                            hash.text.trim(),
                            hours,
                          ),
                        );
                        if (context.mounted) Navigator.pop(context);
                      } on Object catch (e) {
                        if (context.mounted) {
                          setState(() {
                            busy = false;
                            error = e is FormatException ? e.message : '保存失败';
                          });
                        }
                      }
                    },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    url.dispose();
    hash.dispose();
  }

  Future<void> _routing(BuildContext context) async {
    final ips = TextEditingController(
          text: controller.geoRouting.directIPs.join(', '),
        ),
        sites = TextEditingController(
          text: controller.geoRouting.directSites.join(', '),
        ),
        blocked = TextEditingController(
          text: controller.geoRouting.blockSites.join(', '),
        );
    var busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Geo 分类规则'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ips,
                    enabled: !busy,
                    decoration: helpDecoration(
                      '直连 GeoIP 分类',
                      '逗号分隔，如 cn。必须存在于已安装 GeoIP 文件中；留空不使用 IP 库。只写分类名，不加 geoip:。',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: sites,
                    enabled: !busy,
                    decoration: helpDecoration(
                      '直连 GeoSite 分类',
                      '逗号分隔，如 cn。支持文件中的分类及 @属性；留空不按域名直连。',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: blocked,
                    enabled: !busy,
                    decoration: helpDecoration(
                      '阻止 GeoSite 分类',
                      '逗号分隔，如 category-ads-all。命中的域名交给 blackhole 丢弃；仅在相应数据库包含该分类时使用。',
                    ),
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
                      setState(() => busy = true);
                      try {
                        await controller.setGeoRouting(
                          GeoRouting(
                            directIPs: GeoRouting.parseTags(ips.text),
                            directSites: GeoRouting.parseTags(sites.text),
                            blockSites: GeoRouting.parseTags(blocked.text),
                          ),
                        );
                        if (context.mounted) Navigator.pop(context);
                      } on Object catch (e) {
                        if (context.mounted) {
                          setState(() {
                            busy = false;
                            error = e is FormatException
                                ? e.message
                                : '分类校验或保存失败：$e';
                          });
                        }
                      }
                    },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    ips.dispose();
    sites.dispose();
    blocked.dispose();
  }

  Future<void> _tags(BuildContext context, GeoAsset asset) async {
    var query = '';
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final tags = asset.tags
              .where((t) => t.contains(query.toLowerCase()))
              .toList();
          return AlertDialog(
            title: Text('${asset.kind} 分类（${tags.length}）'),
            content: SizedBox(
              width: 520,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: helpDecoration(
                      '搜索分类',
                      '按分类名筛选；点击条目将分类名复制到剪贴板，可粘贴到分流规则。',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: tags.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(tags[i]),
                        trailing: const Icon(Icons.copy, size: 16),
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: tags[i]));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已复制 ${tags[i]}')),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }
}
