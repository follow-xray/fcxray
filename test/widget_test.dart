import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcxray/controllers/app_controller.dart';
import 'package:fcxray/main.dart';
import 'test_support.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('empty state and navigation render at $size', (tester) async {
      tester.view.physicalSize = size;
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
      expect(find.text('尚未连接'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(size.width < 820 ? '节点' : '我的节点'));
      await tester.pumpAndSettle();
      expect(find.text('0 个节点'), findsOneWidget);
      await tester.tap(find.text('导入节点'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
    });
  }
}
