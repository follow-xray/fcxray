import 'package:flutter_test/flutter_test.dart';
import 'package:fcxray/controllers/app_controller.dart';
import 'test_support.dart';
import 'profile_importer_test.dart' show link;

void main() {
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
