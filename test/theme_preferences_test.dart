import 'package:fcxray/controllers/app_controller.dart';
import 'package:fcxray/main.dart';
import 'package:fcxray/ui/calm_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_support.dart';

void main() {
  testWidgets(
    'theme follows system changes unless explicitly selected in settings',
    (t) async {
      final platform = t.platformDispatcher;
      platform.platformBrightnessTestValue = Brightness.light;
      addTearDown(platform.clearPlatformBrightnessTestValue);
      final store = MemoryStore()..value = {'routing': 'bypassLan'};
      final c = AppController(
        backend: FakeBackend(),
        store: store,
        platform: 'android',
      );
      await c.initialize(poll: false);
      expect(c.themeMode.value, ThemeMode.system);
      await t.pumpWidget(FcxrayApp(controller: c));
      Brightness shown() =>
          Theme.of(t.element(find.byType(Scaffold).first)).brightness;
      expect(shown(), Brightness.light);
      platform.platformBrightnessTestValue = Brightness.dark;
      await t.pumpAndSettle();
      expect(shown(), Brightness.dark);
      await t.tap(find.text('设置'));
      await t.pumpAndSettle();
      await t.tap(find.text('浅色'));
      await t.pumpAndSettle();
      expect(shown(), Brightness.light);
      expect(store.value!['themeMode'], 'light');
      await t.tap(find.text('深色'));
      await t.pumpAndSettle();
      platform.platformBrightnessTestValue = Brightness.light;
      await t.pumpAndSettle();
      expect(shown(), Brightness.dark);
      expect(store.value!['themeMode'], 'dark');
      final context = t.element(find.byType(Scaffold).first);
      expect(Calm.of(context).canvas, Calm.night.canvas);
      final reopened = AppController(
        backend: FakeBackend(),
        store: store,
        platform: 'android',
      );
      await reopened.initialize(poll: false);
      expect(reopened.themeMode.value, ThemeMode.dark);
      reopened.dispose();
      await t.tap(find.text('跟随系统'));
      await t.pumpAndSettle();
      expect(shown(), Brightness.light);
      expect(store.value!['themeMode'], 'system');
    },
  );

  test(
    'changing theme during a session persists without touching the active config; failed writes roll back',
    () async {
      final store = MemoryStore(), backend = FakeBackend();
      final c = AppController(
        backend: backend,
        store: store,
        platform: 'android',
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      await c.importText('trojan://sample@localhost:443#Test');
      await c.toggle();
      final active = backend.activeConfig;
      await c.setThemeMode(ThemeMode.dark);
      expect(backend.activeConfig, active);
      expect(c.connected, true);
      store.fail = true;
      await expectLater(c.setThemeMode(ThemeMode.light), throwsStateError);
      expect(c.themeMode.value, ThemeMode.dark);
      expect(store.value!['themeMode'], 'dark');
    },
  );
}
