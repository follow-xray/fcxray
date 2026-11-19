import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../controllers/app_controller.dart';
import '../models/profile.dart';
import 'config_builder.dart';

class DesktopTray with TrayListener, WindowListener {
  DesktopTray(this.controller);
  final AppController controller;
  bool _handling = false;
  bool _openingMenu = false;

  Future<void> install() async {
    await windowManager.ensureInitialized();
    // Enable close-to-tray only once the user has a way to reopen the window.
    await trayManager.setIcon(
      Platform.isMacOS
          ? 'assets/brand/tray-template.png'
          : 'windows/runner/resources/app_icon.ico',
      isTemplate: Platform.isMacOS,
    );
    await trayManager.setToolTip('fcxray');
    trayManager.addListener(this);
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    if (Platform.isMacOS) {
      await const MethodChannel(
        'com.fcxray.client/window',
      ).invokeMethod<void>('enableCloseToTray');
    }
  }

  @override
  void onWindowClose() => unawaited(windowManager.hide());

  Future<void> _show() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() => unawaited(_show());

  @override
  void onTrayIconRightMouseDown() => unawaited(_openMenu());

  Future<void> _openMenu() async {
    if (_openingMenu) return;
    _openingMenu = true;
    try {
      // Build on demand so polling and subscription refreshes can't replace a
      // native menu while the user is choosing a node.
      await trayManager.setContextMenu(buildMenu());
      await trayManager.popUpContextMenu();
    } finally {
      _openingMenu = false;
    }
  }

  Menu buildMenu() {
    final c = controller;
    final node = c.displayProfile;
    String safe(String label) => label
        .replaceAll(RegExp(r'[\r\n\t]'), ' ')
        .replaceAll('&', Platform.isWindows ? '&&' : '&');
    final groups = <String?, List<Profile>>{};
    for (final profile in c.profiles) {
      (groups[profile.subscriptionId] ??= []).add(profile);
    }
    List<MenuItem> nodeItems(List<Profile> profiles) => [
      for (final p in profiles)
        MenuItem.checkbox(
          key: 'node/${p.id}',
          label: safe(p.name),
          checked:
              p.id == node?.id &&
              (!c.connected ||
                  AppController.fingerprint(node!) ==
                      AppController.fingerprint(p)),
        ),
    ];
    final sources = <MenuItem>[];
    for (final group in groups.values) {
      const size = 32;
      final items = group.length <= size
          ? nodeItems(group)
          : [
              for (var i = 0; i < group.length; i += size)
                MenuItem.submenu(
                  label: '${i + 1}–${(i + size).clamp(0, group.length)}',
                  submenu: Menu(
                    items: nodeItems(group.skip(i).take(size).toList()),
                  ),
                ),
            ];
      sources.add(
        MenuItem.submenu(
          label: safe(c.sourceName(group.first)),
          submenu: Menu(items: items),
        ),
      );
    }
    final state = switch (c.status) {
      VpnStatus.connected => '已连接',
      VpnStatus.connecting => '连接中',
      VpnStatus.disconnecting => '断开中',
      VpnStatus.failed => '连接失败',
      VpnStatus.disconnected => '未连接',
    };
    return Menu(
      items: [
        MenuItem(label: state, disabled: true),
        MenuItem(
          label:
              '${c.connected ? "当前节点" : "已选节点"}：${node == null ? "无" : safe(node.name)}',
          disabled: true,
        ),
        MenuItem.submenu(
          label: '路由模式',
          submenu: Menu(
            items: [
              for (final mode in RoutingMode.values)
                MenuItem.checkbox(
                  key: 'routing/${mode.name}',
                  label: mode.label,
                  checked: c.routing == mode,
                  disabled: _handling || !c.resourcesEditable,
                ),
            ],
          ),
        ),
        MenuItem(key: 'show', label: '显示主窗口'),
        MenuItem.separator(),
        MenuItem.submenu(
          label: '切换节点',
          disabled: _handling || !c.resourcesEditable || sources.isEmpty,
          submenu: Menu(items: sources),
        ),
        MenuItem(
          key: 'connect',
          label: '连接',
          disabled: _handling || c.connected || !c.canToggle,
        ),
        MenuItem(
          key: 'disconnect',
          label: '断开',
          disabled: _handling || !c.connected || !c.canToggle,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit',
          label: '退出 fcxray',
          disabled: _handling || c.busy || c.saving,
        ),
      ],
    );
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) =>
      unawaited(handle(menuItem.key));

  Future<void> handle(String? key) async {
    if (key == 'show') {
      await _show();
      return;
    }
    if (_handling || key == null) return;
    _handling = true;
    try {
      final c = controller;
      if (key.startsWith('routing/')) {
        await c.switchRouting(
          RoutingMode.values.byName(key.substring('routing/'.length)),
        );
      } else if (key.startsWith('node/')) {
        await c.switchNode(key.substring(5));
      } else if ((key == 'connect' && !c.connected) ||
          (key == 'disconnect' && c.connected)) {
        await c.toggle();
      } else if (key == 'exit') {
        if (await c.shutdownForExit()) {
          windowManager.removeListener(this);
          trayManager.removeListener(this);
          try {
            await trayManager.destroy();
          } finally {
            await windowManager.destroy();
          }
          return;
        }
      }
      if (c.error != null) await _show();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
      await _show();
    } finally {
      _handling = false;
    }
  }
}
