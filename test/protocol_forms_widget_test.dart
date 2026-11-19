import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcxray/controllers/app_controller.dart';
import 'package:fcxray/main.dart';
import 'package:fcxray/ui/help_fields.dart';
import 'test_support.dart';
import 'live_update_test.dart' show MutableFetcher;
import 'resources_test.dart' show node;

Finder dropdown(String label) => find.byWidgetPredicate(
  (w) =>
      w is DropdownButtonFormField<String> && w.decoration.labelText == label,
);
void main() {
  testWidgets(
    'WireGuard fields, xdrive settings and full JSON editing are available on mobile',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController(
        backend: FakeBackend(),
        store: MemoryStore(),
        platform: 'android',
      );
      await c.initialize(poll: false);
      await tester.pumpWidget(FcxrayApp(controller: c));
      await tester.tap(find.text('节点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手动添加'));
      await tester.pumpAndSettle();
      await tester.tap(dropdown('协议'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('wireguard').last);
      await tester.pumpAndSettle();
      expect(find.text('WireGuard 私钥'), findsOneWidget);
      expect(find.text('Peer Endpoint'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(dropdown('协议'));
      await tester.tap(dropdown('协议'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('vless').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(dropdown('传输协议'));
      await tester.tap(dropdown('传输协议'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('xdrive').last);
      await tester.pumpAndSettle();
      expect(find.text('xdrive 存储服务'), findsOneWidget);
      expect(find.text('远端目录 / Folder ID'), findsOneWidget);
      expect(find.byType(HelpIcon), findsWidgets);
      await tester.ensureVisible(find.text('完整出站 JSON'));
      await tester.tap(find.text('完整出站 JSON'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '完整出站 JSON',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'connected resource controls stay enabled and overview shows frozen active node',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fetch = MutableFetcher(),
          c = AppController(
            backend: FakeBackend(),
            store: MemoryStore(),
            platform: 'android',
            fetcher: MutableFetcher(),
          );
      final source = c.fetcher as MutableFetcher;
      source.payload = fetch.payload;
      await c.initialize(poll: false);
      final id = (await c.addSubscriptions(
        'Source',
        'https://example.com/sub',
        0,
      )).single;
      await c.updateSubscription(id);
      await c.toggle();
      source.payload = node('new.example', 'New');
      await c.updateSubscription(id);
      await tester.pumpWidget(FcxrayApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.textContaining('下次连接生效'), findsOneWidget);
      expect(find.textContaining('Old'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('订阅'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '更新全部'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('规则'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '导入 .dat').first,
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
