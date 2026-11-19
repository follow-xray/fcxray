import 'package:fcxray/controllers/app_controller.dart';
import 'package:fcxray/services/desktop_tray.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_support.dart';

class _Backend extends FakeBackend {
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    String? config,
    String? assetDirectory,
  ]) {
    calls.add(method);
    return super.call(method, config, assetDirectory);
  }

  @override
  Future<void> close() async {
    calls.add('close');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'closing hides the window; tray switches only on request and exits after core cleanup',
    () async {
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in ['window_manager', 'tray_manager']) {
        messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
          calls.add(call.method);
          return call.method == 'isMinimized' ? false : true;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(MethodChannel(name), null),
        );
      }
      final backend = _Backend();
      final c = AppController(
        backend: backend,
        store: MemoryStore(),
        platform: 'windows',
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      await c.importText(
        'trojan://a@localhost:10001#One\ntrojan://b@localhost:10002#Two',
      );
      final tray = DesktopTray(c);
      await tray.handle('node/${c.profiles.last.id}');
      expect(c.connected, false);
      await tray.handle('connect');
      final original = backend.activeConfig;
      tray.onWindowClose();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['hide']);
      expect(backend.calls, ['start']);
      expect(backend.activeConfig, original);
      expect(
        tray.buildMenu().items!.any((item) => item.label == '当前节点：Two'),
        true,
      );
      await tray.handle('show');
      expect(calls, containsAllInOrder(['show', 'focus']));
      await tray.handle('node/${c.profiles.first.id}');
      expect(c.activeProfile!.name, 'One');
      expect(backend.calls, ['start', 'stop', 'start']);
      await tray.handle('disconnect');
      expect(tray.buildMenu().getMenuItem('disconnect')!.disabled, true);
      await tray.handle('connect');
      await tray.handle('exit');
      expect(backend.calls, [
        'start',
        'stop',
        'start',
        'stop',
        'start',
        'stop',
        'close',
      ]);
      expect(calls.sublist(calls.length - 2), ['destroy', 'destroy']);
    },
  );
}
