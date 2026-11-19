import 'dart:async';
import 'dart:convert';
import 'package:fcxray/controllers/app_controller.dart';
import 'package:fcxray/main.dart';
import 'package:fcxray/services/config_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_support.dart';

class SlowStore extends MemoryStore {
  final pending = Completer<Map<String, dynamic>?>();
  @override
  Future<Map<String, dynamic>?> read() => pending.future;
}

Map<String, dynamic> saved([String name = 'Saved']) => {
  'schemaVersion': 3,
  'profiles': [
    {
      'name': name,
      'id': 'one',
      'outbound': {'protocol': 'freedom', 'settings': {}, 'tag': 'proxy'},
    },
  ],
  'subscriptions': [],
  'selectedId': 'one',
  'themeMode': 'dark',
  'routing': 'direct',
};

void main() {
  testWidgets(
    'first frame renders while storage hangs; timeout offers recovery; late read is ignored',
    (t) async {
      final slow = SlowStore(),
          c = AppController(
            backend: FakeBackend(),
            store: slow,
            platform: 'android',
          );
      await t.pumpWidget(FcxrayApp(controller: c));
      final startup = c.initialize(poll: false);
      await t.pump();
      expect(find.text('正在读取配置…'), findsOneWidget);
      await t.pump(const Duration(seconds: 11));
      await startup;
      await t.pump();
      expect(find.text('从文件恢复'), findsOneWidget);
      slow.pending.complete(saved());
      await t.pump();
      expect(c.loaded, false);
      expect(t.takeException(), isNull);
    },
  );

  for (final missing in [true, false]) {
    testWidgets('restore local backup from startup (missing=$missing)', (
      t,
    ) async {
      final raw = missing
          ? null
          : {
              ...saved(),
              'profiles': [
                {
                  'id': 'bad',
                  'name': 'bad',
                  'outbound': {
                    'protocol': 'dns',
                    'settings': {'rewritePort': []},
                  },
                },
              ],
            };
      final primary = MemoryStore()..value = raw;
      final backup = MemoryStore()
        ..value = ConfigBackup(DateTime.utc(2026), saved()).toJson();
      final c = AppController(
        backend: FakeBackend(),
        store: primary,
        backupStore: backup,
        platform: 'android',
      );
      await c.initialize(poll: false);
      expect(c.loaded, false);
      expect(primary.value, same(raw));
      await t.pumpWidget(FcxrayApp(controller: c));
      await t.tap(find.text('恢复自动备份'));
      await t.pumpAndSettle();
      await t.tap(find.text('恢复').last);
      await t.pumpAndSettle();
      expect(find.text('连接总览'), findsOneWidget);
      expect(c.selected?.name, 'Saved');
      expect(c.connected, false);
      expect(backup.value!['state']['selectedId'], 'one');
      expect(t.takeException(), isNull);
    });
  }

  test(
    'successful saves rotate verified state and failed recovery preserves both copies',
    () async {
      final primary = MemoryStore(), backup = MemoryStore();
      final c = AppController(
        backend: FakeBackend(),
        store: primary,
        backupStore: backup,
        platform: 'macos',
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      expect(c.loaded, true);
      await c.importText('trojan://secret@example.com:443#One');
      expect(
        ConfigBackup.fromJson(backup.value!).state['profiles'],
        hasLength(1),
      );
      await c.importText('trojan://next@other.example:443#Two');
      final old = c.localBackup!;
      expect(old.state['profiles'], hasLength(1));
      final lastGood = primary.value;
      primary.fail = true;
      await expectLater(c.restoreBackup(old), throwsStateError);
      expect(primary.value, same(lastGood));
      expect(c.profiles, hasLength(2));
      expect(c.localBackup, same(old));
      primary.fail = false;
      await expectLater(
        c.restoreBackup(
          ConfigBackup(old.savedAt, {...saved(), 'schemaVersion': 999}),
        ),
        throwsFormatException,
      );
      expect(primary.value, same(lastGood));
      await c.restoreBackup(old);
      expect(c.profiles, hasLength(1));
      expect(c.localBackup!.state['profiles'], hasLength(2));
    },
  );

  test(
    'empty workspace leaves damaged primary untouched until the next save',
    () async {
      final broken = {...saved(), 'profiles': 'damaged'};
      final primary = MemoryStore()..value = broken;
      final backup = MemoryStore()
        ..value = ConfigBackup(DateTime.utc(2026), saved()).toJson();
      final c = AppController(
        backend: FakeBackend(),
        store: primary,
        backupStore: backup,
        platform: 'android',
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      await c.restoreBackup(null);
      expect(c.loaded, true);
      expect(c.profiles, isEmpty);
      expect(primary.value, same(broken));
      await c.importText('trojan://new@local.example:443#New');
      expect(c.localBackup!.state['selectedId'], 'one');
      expect(primary.value!['profiles'], hasLength(1));
    },
  );

  test(
    'restoring preferences keeps an existing VPN on its current session',
    () async {
      final backend = FakeBackend();
      final c = AppController(
        backend: backend,
        store: MemoryStore(),
        platform: 'android',
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      await c.importText('trojan://p@example.com:443#Original');
      await c.toggle();
      final running = backend.activeConfig;
      await c.restoreBackup(
        ConfigBackup(DateTime.utc(2026), saved('Recovered')),
      );
      expect(c.connected, true);
      expect(c.selected?.name, 'Recovered');
      expect(c.activeProfile?.name, 'Original');
      expect(backend.activeConfig, running);
    },
  );
  test(
    'password-encrypted portable backup round trip and wrong password',
    () async {
      final source = ConfigBackup(DateTime.utc(2026), saved('private-node'));
      final bytes = await encryptBackup(source, 'sample-passphrase');
      expect(utf8.decode(bytes), isNot(contains('private-node')));
      final reopened = await decryptBackup(bytes, 'sample-passphrase');
      expect(reopened.state, source.state);
      await expectLater(decryptBackup(bytes, 'wrong'), throwsA(anything));
      final plain = source.toJson();
      (plain['state'] as Map)['themeMode'] = 'light';
      expect(() => ConfigBackup.fromJson(plain), throwsFormatException);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
