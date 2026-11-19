import 'calm_theme.dart';
import 'config_recovery.dart';
import 'format_bytes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/app_controller.dart';
import '../services/config_builder.dart';
import 'config_viewer.dart';
import 'connection_panel.dart';
import 'geo_panel.dart';
import 'help_fields.dart';
import 'nodes_panel.dart';
import 'routing_preferences.dart';
import 'subscriptions_panel.dart';
import 'subscription_agent_setting.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int page = 0;
  static const titles = ['连接总览', '我的节点', '订阅管理', '路由与规则', '连接设置', '运行日志'];
  static const navIcons = [
    Icons.dashboard_outlined,
    Icons.dns_outlined,
    Icons.rss_feed,
    Icons.public,
    Icons.tune,
    Icons.terminal,
  ];
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncPolling(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncPolling(state);
  }

  void _syncPolling(AppLifecycleState? state) {
    c.setPollingView(
      visible:
          state == null ||
          state == AppLifecycleState.resumed ||
          state == AppLifecycleState.inactive,
      overview: page == 0,
    );
  }

  void _goTo(int next) {
    if (next == page) return;
    setState(() => page = next);
    _syncPolling(WidgetsBinding.instance.lifecycleState);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        if (!c.loaded) return StartupPanel(c);
        final wide = constraints.maxWidth >= 820;
        final scaffold = Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (wide) _sidebar(),
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          wide ? 32 : 20,
                          24,
                          wide ? 32 : 20,
                          16,
                        ),
                        child: Row(
                          children: [
                            if (!wide) ...[
                              Image.asset(
                                'assets/brand/logo.png',
                                width: 34,
                                height: 34,
                                semanticLabel: 'fcxray',
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.shield_outlined),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Text(
                                titles[page],
                                style: TextStyle(
                                  fontSize: wide ? 30 : 24,
                                  letterSpacing: -.8,
                                  fontWeight: FontWeight.w700,
                                  color: Calm.of(context).ink,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '查看当前配置',
                              onPressed: c.loaded && !c.busy
                                  ? () => showConfigViewer(context, c)
                                  : null,
                              icon: const Icon(Icons.data_object),
                            ),
                          ],
                        ),
                      ),
                      if (c.saving) const LinearProgressIndicator(minHeight: 2),
                      Expanded(
                        child: SingleChildScrollView(
                          key: PageStorageKey(page),
                          padding: EdgeInsets.fromLTRB(
                            wide ? 32 : 20,
                            8,
                            wide ? 32 : 20,
                            28,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1100),
                              child: switch (page) {
                                0 => _overview(),
                                1 => NodesPanel(
                                  controller: c,
                                  onImport: _import,
                                ),
                                2 => SubscriptionsPanel(controller: c),
                                3 => GeoPanel(controller: c),
                                4 => _settings(),
                                _ => _logs(),
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: page < 5 ? page : 4,
                  onDestinationSelected: _goTo,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      label: '总览',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.dns_outlined),
                      label: '节点',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.rss_feed),
                      label: '订阅',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.public),
                      label: '规则',
                    ),
                    NavigationDestination(icon: Icon(Icons.tune), label: '设置'),
                  ],
                ),
        );
        return PopScope<Object?>(
          canPop: c.platform != 'android' || page == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && c.platform == 'android' && page != 0) {
              _goTo(page == 5 ? 4 : 0);
            }
          },
          child: scaffold,
        );
      },
    ),
  );

  Widget _sidebar() => Container(
    width: 212,
    decoration: BoxDecoration(
      color: Calm.of(context).inset,
      border: Border(right: BorderSide(color: Calm.of(context).line)),
    ),
    child: Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 30, 16, 28),
            child: Row(
              children: [
                Image.asset(
                  'assets/brand/logo.png',
                  width: 44,
                  height: 44,
                  semanticLabel: 'fcxray',
                  errorBuilder: (_, _, _) => const Icon(Icons.shield_outlined),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'fcxray',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < titles.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 3,
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      selected: page == i,
                      selectedTileColor: Calm.of(context).lilac,
                      leading: Icon(navIcons[i], size: 21),
                      title: Text(titles[i]),
                      onTap: () => _goTo(i),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _overview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (c.pendingChanges) ...[
        Card(
          color: Calm.of(context).mint,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '更新已保存，下次连接生效。路由规则也可在设置中立即应用。\n下次节点：${c.selected?.name ?? '尚未选择'}',
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
      ConnectionPanel(c, onImport: _import, onManageNodes: () => _goTo(1)),
      if (c.profiles.isEmpty && c.subscriptions.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: BackupActions(c, allowExport: false),
        ),
      if (c.error != null)
        Padding(padding: const EdgeInsets.only(top: 16), child: _errorCard()),
      const SizedBox(height: 20),
      const Text(
        '会话统计',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxWidth < 480;
          final columns = box.maxWidth < 295 ? 1 : 3;
          final width = (box.maxWidth - 12 * (columns - 1)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metric(
                '下载速度',
                '${formatBytes(c.downloadRate)}/s',
                Icons.south_west_rounded,
                width,
                compact,
                Calm.of(context).mint,
                Calm.of(context).pine,
              ),
              _metric(
                '上传速度',
                '${formatBytes(c.uploadRate)}/s',
                Icons.north_east_rounded,
                width,
                compact,
                Calm.of(context).lilac,
                Calm.of(context).iris,
              ),
              _metric(
                '会话流量',
                formatBytes((c.upload + c.download).toDouble()),
                Icons.swap_vert_rounded,
                width,
                compact,
                Calm.of(context).peach,
                Calm.of(context).clay,
              ),
            ],
          );
        },
      ),
    ],
  );

  Widget _metric(
    String label,
    String value,
    IconData icon,
    double width,
    bool compact,
    Color tint,
    Color ink,
  ) => SizedBox(
    width: width,
    child: SoftSurface(
      radius: 20,
      padding: EdgeInsets.all(compact ? 10 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TintIcon(icon, fill: tint, ink: ink),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(color: Calm.of(context).muted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: Calm.of(context).ink,
              fontSize: compact ? 17 : 25,
              fontWeight: FontWeight.w600,
              letterSpacing: -.6,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _errorCard() => Card(
    color: Calm.of(context).blush,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            c.error!,
            style: TextStyle(fontSize: 12, color: Calm.of(context).muted),
          ),
        ],
      ),
    ),
  );

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SoftSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '外观主题',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
              ],
              selected: {c.themeMode.value},
              onSelectionChanged: c.resourcesEditable
                  ? (selection) async {
                      try {
                        await c.setThemeMode(selection.single);
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('主题保存失败，已恢复原选择。')),
                          );
                        }
                      }
                    }
                  : null,
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      SubscriptionAgentSetting(c),
      const SizedBox(height: 18),
      SoftSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '备份与恢复',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            BackupActions(c),
          ],
        ),
      ),
      const SizedBox(height: 18),
      if (c.error != null) _errorCard(),
      if (!c.editable)
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text('更改流量接管方式前请断开连接。'),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<ConnectionMode>(
                initialValue: c.mode,
                isExpanded: true,
                decoration: helpDecoration(
                  '流量接管',
                  'VPN 模式通过系统 TUN 接管设备流量；本地代理模式只处理手动配置了 SOCKS5 / HTTP 代理的应用。',
                ),
                items: [
                  const DropdownMenuItem(
                    value: ConnectionMode.vpn,
                    child: Text('VPN · TUN 全设备流量'),
                  ),
                  if (c.platform != 'android')
                    const DropdownMenuItem(
                      value: ConnectionMode.proxy,
                      child: Text('本地代理 · 手动配置应用'),
                    ),
                ],
                onChanged: c.editable ? (v) => c.settings(v!, c.routing) : null,
              ),
              if (c.mode == ConnectionMode.proxy)
                const SelectableText(
                  'SOCKS5  127.0.0.1:10808\nHTTP  127.0.0.1:10809',
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      SoftSurface(child: RoutingPreferences(c)),
      const SizedBox(height: 18),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => showConfigViewer(context, c),
                    icon: const Icon(Icons.data_object),
                    label: const Text('查看配置'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _goTo(5),
                    icon: const Icon(Icons.terminal),
                    label: const Text('运行日志'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text('fcxray 0.7.1 · Xray-core ${c.coreVersion}'),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'fcxray',
                  applicationVersion: '0.7.1',
                ),
                child: const Text('第三方许可'),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _logs() => SoftSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '本次运行 · ${c.logs.length} 条记录',
          style: TextStyle(color: Calm.of(context).muted),
        ),
        if (c.logs.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 18), child: Text('暂无日志')),
        for (final entry in c.logs) ...[
          const Divider(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.circle, size: 9, color: Calm.of(context).iris),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(
                  entry,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  Future<void> _import() async {
    final text = TextEditingController();
    String? error;
    bool saving = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('导入节点'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '粘贴分享链接、Base64 订阅内容或 Xray 出站 JSON。支持多行批量导入。',
                    style: TextStyle(
                      color: Calm.of(context).muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: text,
                    minLines: 5,
                    maxLines: 9,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: helpDecoration(
                      '节点配置',
                      '可粘贴分享链接、Base64 订阅内容或 Xray JSON；订阅网址请使用订阅管理页。',
                      hint: 'vless://…\ntrojan://…',
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
                  TextButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            if (context.mounted && data != null) {
                              text.text = data.text ?? '';
                            }
                          },
                    icon: const Icon(Icons.content_paste, size: 16),
                    label: const Text('从剪贴板粘贴'),
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
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      update(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final count = await c.importText(text.text);
                        if (context.mounted) Navigator.pop(context);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text('已导入 $count 个新节点')),
                          );
                        }
                      } on Object catch (e) {
                        if (context.mounted) {
                          update(() {
                            saving = false;
                            error = e is FormatException
                                ? e.message
                                : '导入失败，请检查配置或安全存储权限。';
                          });
                        }
                      }
                    },
              child: Text(saving ? '正在导入…' : '导入'),
            ),
          ],
        ),
      ),
    );
    // The dialog's exit animation may still reference its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
  }
}
