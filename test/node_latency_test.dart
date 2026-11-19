import 'dart:async';
import 'package:fcxray/controllers/app_controller.dart';
import 'package:fcxray/services/node_latency.dart';
import 'package:fcxray/services/profile_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_support.dart';

void main() {
  test(
    'batch tests other nodes without changing a live session or selection',
    () async {
      final backend = FakeBackend();
      final latency = NodeLatency(
        measure: (p) async => p.name == 'B' ? 12 : 57,
      );
      final c = AppController(
        backend: backend,
        store: MemoryStore(),
        platform: 'android',
        latency: latency,
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      await c.importText(
        'trojan://a@localhost:10001#A\ntrojan://b@localhost:10002#B',
      );
      await c.toggle();
      final running = backend.activeConfig;
      final id = c.selectedId;
      await latency.run(c.profiles);
      expect(latency.sorted(c.profiles).map((p) => p.name), ['B', 'A']);
      expect(c.profiles.first.name, 'A');
      expect(c.selectedId, id);
      expect(c.connected, true);
      expect(backend.activeConfig, running);
      expect(c.activeProfile?.name, 'A');
    },
  );

  test(
    'cancellation stops queued tests and utility profiles never open connections',
    () async {
      final done = Completer<int>();
      var calls = 0;
      final latency = NodeLatency(
        concurrency: 1,
        measure: (_) {
          calls++;
          return done.future;
        },
      );
      final nodes = ProfileImporter.parse(
        'trojan://a@localhost:10001#A\ntrojan://b@localhost:10002#B',
      );
      final utility = ProfileImporter.parse('{"protocol":"blackhole"}').single;
      final run = latency.run([utility, ...nodes]);
      latency.stopQueue();
      done.complete(-1);
      await run;
      expect(calls, 1);
      expect(latency.label(utility), '不适用');
      expect(latency.label(nodes.first), '测试失败');
      expect(latency.label(nodes.last), '未测试');
      latency.dispose();
    },
  );
}
