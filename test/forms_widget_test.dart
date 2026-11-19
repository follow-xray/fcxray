import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcxray/controllers/app_controller.dart';
import 'package:fcxray/main.dart';
import 'package:fcxray/ui/help_fields.dart';
import 'test_support.dart';

void main() {
  testWidgets('subscriptions show provider usage and omit missing fields', (
    t,
  ) async {
    final store = MemoryStore()
      ..value = {
        'subscriptions': [
          {
            'id': 'sub',
            'name': 'Provider',
            'url': 'https://example.com/sub',
            'usage': {'download': 2048, 'total': 8192, 'expire': 1893456000},
          },
        ],
      };
    final c = AppController(
      backend: FakeBackend(),
      store: store,
      platform: 'android',
    );
    await c.initialize(poll: false);
    await t.pumpWidget(FcxrayApp(controller: c));
    await t.tap(find.text('订阅'));
    await t.pumpAndSettle();
    expect(find.textContaining('已下载 2.0 KB · 总配额 8.0 KB · 到期'), findsOneWidget);
    expect(find.textContaining('已上传'), findsNothing);
  });
  testWidgets('node list switches a live session and shows the active node', (
    t,
  ) async {
    final c = AppController(
      backend: FakeBackend(),
      store: MemoryStore(),
      platform: 'android',
    );
    await c.initialize(poll: false);
    await c.importText(
      'trojan://p@one.example:443#First\ntrojan://p@two.example:443#Second',
    );
    await c.toggle();
    await t.pumpWidget(FcxrayApp(controller: c));
    await t.tap(find.text('节点'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Second'));
    await t.tap(find.text('Second'));
    await t.pumpAndSettle();
    expect(c.activeProfile!.name, 'Second');
    expect(c.connected, true);
  });
  testWidgets('parameter help opens by touch and mouse hover', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: HelpIcon('Example parameter help'))),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text('Example parameter help'), findsOneWidget);
    Tooltip.dismissAllToolTips();
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.help_outline)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Example parameter help'), findsOneWidget);
    await mouse.removePointer();
  });
  testWidgets('subscription agent dialog validates and saves a custom header', (
    t,
  ) async {
    final c = AppController(
      backend: FakeBackend(),
      store: MemoryStore(),
      platform: 'android',
    );
    await c.initialize(poll: false);
    await t.pumpWidget(FcxrayApp(controller: c));
    await t.tap(find.text('设置'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('订阅 User-Agent'));
    await t.tap(find.text('订阅 User-Agent'));
    await t.pumpAndSettle();
    await t.tap(find.text('Xray（v2rayN）').last);
    await t.pumpAndSettle();
    await t.tap(find.text('自定义').last);
    await t.pumpAndSettle();
    await t.tap(find.text('保存'));
    await t.pumpAndSettle();
    expect(find.text('请输入非空的单行 ASCII User-Agent'), findsOneWidget);
    await t.enterText(find.byType(TextFormField), 'Demo/3');
    await t.tap(find.text('保存'));
    await t.pumpAndSettle();
    expect(c.subscriptionHeader, 'Demo/3');
    expect(find.text('自定义 · Demo/3'), findsOneWidget);
  });

  testWidgets('Android back unwinds a dialog, logs, and settings in order', (
    t,
  ) async {
    final c = AppController(
      backend: FakeBackend(),
      store: MemoryStore(),
      platform: 'android',
    );
    await c.initialize(poll: false);
    await t.pumpWidget(FcxrayApp(controller: c));
    await t.tap(find.text('设置'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('订阅 User-Agent'));
    await t.tap(find.text('订阅 User-Agent'));
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('连接设置'), findsOneWidget);
    final logs = find.text('运行日志');
    await t.ensureVisible(logs);
    await t.tap(logs);
    await t.pumpAndSettle();
    expect(find.textContaining('本次运行'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('连接设置'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('连接总览'), findsOneWidget);
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'manual form, subscriptions, rules, and config are reachable at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = AppController(
          backend: FakeBackend(),
          store: MemoryStore(),
          platform: 'macos',
        );
        await c.initialize(poll: false);
        await tester.pumpWidget(FcxrayApp(controller: c));
        await tester.tap(find.text(width < 820 ? '节点' : '我的节点'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手动添加'));
        await tester.pumpAndSettle();
        expect(find.text('协议'), findsOneWidget);
        expect(find.byType(HelpIcon), findsWidgets);
        expect(tester.takeException(), isNull);
        Finder input(String label) => find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        );
        await tester.enterText(input('节点名称'), 'Manual node');
        await tester.enterText(input('服务器地址'), 'example.com');
        await tester.ensureVisible(input('UUID / 用户 ID'));
        await tester.enterText(
          input('UUID / 用户 ID'),
          '11111111-1111-4111-8111-111111111111',
        );
        await tester.tap(find.text('校验并保存'));
        await tester.pumpAndSettle();
        expect(c.profiles, hasLength(1));
        await tester.tap(find.text(width < 820 ? '订阅' : '订阅管理'));
        await tester.pumpAndSettle();
        expect(find.text('添加订阅 / 批量导入'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('添加订阅 / 批量导入'));
        await tester.pumpAndSettle();
        expect(find.text('自动更新周期'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text(width < 820 ? '规则' : '路由与规则'));
        await tester.pumpAndSettle();
        expect(find.text('GeoIP · IP 地址库'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('查看当前配置'));
        await tester.pumpAndSettle();
        expect(find.text('下次启动配置 · 尚未应用'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
