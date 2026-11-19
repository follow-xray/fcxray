import 'package:fcxray/controllers/app_controller.dart';
import 'package:fcxray/models/route_override.dart';
import 'package:fcxray/ui/routing_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_support.dart';
import 'package:fcxray/services/rule_exchange.dart';
import 'package:fcxray/main.dart';
import 'package:fcxray/services/config_builder.dart';
import 'dart:convert';

void main() {
  test(
    'rule exchange preserves order and disabled state and rejects invalid batches',
    () {
      final rules = [
        RouteOverride.parse(
          TargetKind.domain,
          'example.com',
          RouteAction.block,
          enabled: false,
        ),
        RouteOverride.parse(TargetKind.ip, '10.0.0.0/8', RouteAction.direct),
      ];
      final text = RuleExchange.encode(rules);
      expect(
        RuleExchange.decode(text).map((r) => r.toJson()),
        rules.map((r) => r.toJson()),
      );
      final first = rules.first.toJson();
      for (final value in [
        [first, first],
        [
          first,
          {...first, 'action': 'unknown'},
        ],
        [
          {...first, 'enabled': 'false'},
        ],
        {'format': 'other', 'version': 1, 'rules': []},
      ]) {
        expect(
          () => RuleExchange.decode(jsonEncode(value)),
          throwsFormatException,
        );
      }
    },
  );
  testWidgets('home mode control selects direct without a node', (t) async {
    final c = AppController(
      backend: FakeBackend(),
      platform: 'android',
      store: MemoryStore(),
    );
    await c.initialize(poll: false);
    await t.pumpWidget(FcxrayApp(controller: c));
    await t.tap(find.text('直连'));
    await t.pumpAndSettle();
    expect(c.routing, RoutingMode.direct);
    expect(c.canToggle, true);
  });
  testWidgets('settings bulk-adds rules, toggles them, and changes mode', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(
      backend: FakeBackend(),
      platform: 'android',
      store: MemoryStore(),
    );
    addTearDown(c.dispose);
    await c.initialize(poll: false);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: c,
              builder: (_, _) => RoutingPreferences(c),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('添加规则'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'example.com\nexample.net');
    await t.tap(find.byType(DropdownButtonFormField<RouteAction>));
    await t.pumpAndSettle();
    await t.tap(find.text('拒绝').last);
    await t.pumpAndSettle();
    await t.tap(find.text('保存'));
    await t.pumpAndSettle();
    expect(c.overrides.map((r) => r.target), ['example.com', 'example.net']);
    expect(c.overrides.first.action, RouteAction.block);
    await t.tap(find.byType(Checkbox).first);
    await t.pumpAndSettle();
    expect(c.overrides.first.enabled, false);
    await t.tap(find.byTooltip('规则操作').first);
    await t.pumpAndSettle();
    await t.tap(find.text('下移'));
    await t.pumpAndSettle();
    expect(c.overrides.last.target, 'example.com');
    expect(find.text('导入 JSON'), findsOneWidget);
    expect(find.text('导出 JSON'), findsOneWidget);
    expect(find.text('立即应用'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
