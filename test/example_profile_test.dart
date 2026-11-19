import 'package:fcxray/controllers/app_controller.dart';
import 'package:fcxray/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:fcxray/services/manual_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  setUp(() {
    rootBundle.evict('assets/examples/vless-vision-tcp.json');
    rootBundle.evict('assets/examples/vless-vision-tcp-reality.json');
  });
  testWidgets('bundled Vision template creates a new editable node', (
    tester,
  ) async {
    final c = AppController(
      backend: FakeBackend(),
      store: MemoryStore(),
      platform: 'android',
    );
    await c.initialize(poll: false);
    await tester.pumpWidget(FcxrayApp(controller: c));
    await tester.tap(find.text('节点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('示例配置'));
    await tester.pumpAndSettle();
    expect(find.text('VLESS + Vision + TCP'), findsOneWidget);
    await tester.tap(find.text('用示例新建节点'));
    await tester.pumpAndSettle();
    expect(c.profiles, isEmpty);
    await tester.tap(find.text('校验并保存'));
    await tester.pumpAndSettle();
    final fields = ManualProfile.fields(c.profiles.single);
    expect(fields['protocol'], 'vless');
    expect(fields['network'], 'tcp');
    expect(fields['flow'], 'xtls-rprx-vision');
    expect(fields['security'], 'tls');
    expect(fields['sni'], 'vpn.example.com');
    expect(fields['mux'], 'false');
    expect(c.connected, false);
  });
  testWidgets('REALITY template saves the five entered server values', (
    tester,
  ) async {
    final c = AppController(
      backend: FakeBackend(),
      store: MemoryStore(),
      platform: 'android',
    );
    await c.initialize(poll: false);
    await tester.pumpWidget(FcxrayApp(controller: c));
    for (final label in ['节点', '示例配置', 'REALITY', '用示例新建节点']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    final publicKey = base64UrlEncode(
      List.generate(32, (i) => i + 1),
    ).replaceAll('=', '');
    final values = {
      '服务器地址': '192.0.2.5',
      'UUID': '22222222-2222-4222-8222-222222222222',
      'SNI': 'sni.example.net',
      'REALITY 公钥': publicKey,
      'shortId': 'abcd1234',
    };
    for (final field in values.entries) {
      final input = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == field.key,
      );
      await tester.ensureVisible(input);
      await tester.enterText(input, field.value);
    }
    await tester.tap(find.text('校验并保存'));
    await tester.pumpAndSettle();
    final fields = ManualProfile.fields(c.profiles.single);
    expect(fields['address'], values['服务器地址']);
    expect(fields['credential'], values['UUID']);
    expect(fields['sni'], values['SNI']);
    expect(fields['publicKey'], publicKey);
    expect(fields['shortId'], 'abcd1234');
    expect(fields['protocol'], 'vless');
    expect(fields['flow'], 'xtls-rprx-vision');
    expect(fields['network'], 'tcp');
    expect(fields['security'], 'reality');
    expect(fields['port'], '443');
    expect(fields['mux'], 'false');
  });
}
