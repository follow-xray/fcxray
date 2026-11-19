import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcxray/controllers/app_controller.dart';
import 'test_support.dart';
import 'profile_importer_test.dart' show link;

class PollBackend extends FakeBackend {
  int polls = 0;
  Completer<Map<String, dynamic>>? delayed;
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    String? config,
    String? assets,
  ]) {
    if (method == 'status') {
      polls++;
      if (delayed != null) return delayed!.future;
    }
    return super.call(method, config, assets);
  }
}

void main() {
  testWidgets(
    'hidden status polls slow down and resume immediately without idle rebuilds',
    (t) async {
      final backend = PollBackend();
      final c = AppController(
        backend: backend,
        store: MemoryStore(),
        platform: 'macos',
      );
      await c.initialize();
      int changes = 0;
      c.addListener(() => changes++);
      final initial = backend.polls;
      c.setPollingView(visible: false, overview: true);
      await t.pump(const Duration(seconds: 29));
      expect(backend.polls, initial);
      await t.pump(const Duration(seconds: 1));
      expect(backend.polls, initial + 1);
      c.setPollingView(visible: true, overview: true);
      await t.pump();
      expect(backend.polls, initial + 2);
      await t.pump(const Duration(seconds: 1));
      expect(backend.polls, initial + 3);
      expect(changes, 0);
      c.dispose();
    },
  );

  test('a late status response cannot undo a newly started session', () async {
    final backend = PollBackend();
    final c = AppController(
      backend: backend,
      store: MemoryStore(),
      platform: 'windows',
    );
    addTearDown(c.dispose);
    await c.initialize(poll: false);
    await c.importText(link);
    backend.delayed = Completer();
    final old = c.refresh();
    await c.toggle();
    backend.delayed!.complete({'running': false});
    await old;
    expect(c.connected, true);
    expect(c.activeProfile?.id, c.selectedId);
  });

  test(
    'imports deduplicate, persist and roll back on secure-storage failure',
    () async {
      final store = MemoryStore();
      final c = AppController(
        backend: FakeBackend(),
        store: store,
        platform: 'macos',
      );
      await c.initialize(poll: false);
      expect(await c.importText('$link\n$link'), 1);
      expect(await c.importText(link), 0);
      final id = c.selectedId;
      store.fail = true;
      await c.remove(id!);
      expect(c.profiles, hasLength(1));
      expect(c.selectedId, id);
      c.dispose();
    },
  );
  test(
    'only successful native start means connected; handles system revocation',
    () async {
      final backend = FakeBackend();
      final c = AppController(
        backend: backend,
        store: MemoryStore(),
        platform: 'android',
      );
      await c.initialize(poll: false);
      await c.importText(link);
      backend.fail = true;
      await c.toggle();
      expect(c.status, VpnStatus.failed);
      backend.fail = false;
      await c.toggle();
      expect(c.connected, true);
      expect(c.editable, false);
      backend.running = false;
      await c.refresh();
      expect(c.status, VpnStatus.disconnected);
      c.dispose();
    },
  );
}
