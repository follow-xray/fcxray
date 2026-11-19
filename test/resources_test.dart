import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcxray/controllers/app_controller.dart';
import 'package:fcxray/models/resources.dart';
import 'package:fcxray/services/core_backend.dart';
import 'package:fcxray/services/geo_store.dart';
import 'package:fcxray/services/resource_fetcher.dart';
import 'package:fcxray/services/config_builder.dart';
import 'package:fcxray/services/profile_importer.dart';
import 'test_support.dart';

String node(String host, String name) =>
    'vless://11111111-1111-4111-8111-111111111111@$host:443?security=tls#$name';
List<int> field(int tag, List<int> bytes) => [tag, bytes.length, ...bytes];
List<int> ipFixture() => field(10, [
  ...field(10, utf8.encode('CN')),
  ...field(18, [
    ...field(10, [192, 0, 2, 0]),
    16,
    24,
  ]),
]);
List<int> siteFixture() => field(10, [
  ...field(10, utf8.encode('CN')),
  ...field(18, [8, 3, ...field(18, utf8.encode('example.com'))]),
]);

class RecordingFetcher extends ResourceFetcher {
  int requests = 0;
  Uri? lastProxy;
  @override
  Future<String> subscription(
    String url, {
    String userAgent = SubscriptionAgent.xrayHeader,
    Uri? proxy,
    void Function(DownloadRoute)? onRoute,
  }) async {
    lastProxy = proxy;
    requests++;
    return node('scheduled.example', 'Scheduled');
  }
}

void main() {
  test(
    'saving stale resource settings cannot revert a completed update',
    () async {
      final c = AppController(
        backend: FakeBackend(),
        store: MemoryStore(),
        platform: 'android',
        fetcher: RecordingFetcher(),
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      final id = (await c.addSubscriptions(
        'Original',
        'https://example.com/sub',
        24,
      )).single;
      final opened = c.subscriptions.single;
      await c.updateSubscription(id);
      final completedAt = c.subscriptions.single.updatedAt;
      await c.editSubscription(
        Subscription(
          id: opened.id,
          name: 'Edited',
          url: opened.url,
          autoHours: 6,
        ),
      );
      expect(c.subscriptions.single.updatedAt, completedAt);
      expect(c.subscriptions.single.name, 'Edited');
      final oldGeo = c.geoAssets['geoip']!;
      final hash = List.filled(64, 'a').join();
      c.geoAssets = {
        ...c.geoAssets,
        'geoip': GeoAsset.fromJson({
          ...oldGeo.toJson(),
          'fileName': 'geoip-$hash.dat',
          'hash': hash,
          'size': 123,
          'tags': ['cn'],
          'updatedAt': DateTime.now().toIso8601String(),
        }),
      };
      await c.configureGeo(
        oldGeo.withSettings('https://example.com/geoip.dat', '', 6),
      );
      expect(c.geoAssets['geoip']!.fileName, 'geoip-$hash.dat');
      expect(c.geoAssets['geoip']!.hash, hash);
      expect(c.geoAssets['geoip']!.url, 'https://example.com/geoip.dat');
    },
  );

  test(
    'scheduled updates run through the active proxy without restarting and respect the interval',
    () async {
      final fetcher = RecordingFetcher();
      final c = AppController(
        backend: FakeBackend(),
        store: MemoryStore(),
        platform: 'android',
        fetcher: fetcher,
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      await c.importText(node('manual.example', 'Manual'));
      await c.addSubscriptions('Scheduled', 'https://example.com/sub', 24);
      await c.toggle();
      await c.updateDue();
      expect(fetcher.requests, 1);
      expect(fetcher.lastProxy?.port, 10809);
      expect(c.connected, true);
      await c.toggle();
      await c.updateDue();
      expect(fetcher.requests, 1);
      expect(c.profiles, hasLength(2));
      await c.updateDue();
      expect(fetcher.requests, 1);
    },
  );

  test(
    'multiple subscriptions isolate updates, preserve selection, and keep last good nodes on errors',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var payloadA = '${node('a.example', 'A')}\n${node('b.example', 'B')}';
      server.listen((request) async {
        request.response.write(
          request.uri.path == '/a' ? payloadA : node('c.example', 'C'),
        );
        await request.response.close();
      });
      final store = MemoryStore();
      final c = AppController(
        backend: FakeBackend(),
        store: store,
        platform: 'macos',
        fetcher: const ResourceFetcher(allowLoopbackHttp: true),
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      await c.importText(node('manual.example', 'Manual'));
      final ids = await c.addSubscriptions(
        'Test',
        'http://127.0.0.1:${server.port}/a\nhttp://127.0.0.1:${server.port}/b',
        24,
      );
      await c.updateSubscriptions(ids);
      expect(c.profiles, hasLength(4));
      final selected = c.profiles.firstWhere((p) => p.host == 'b.example');
      await c.select(selected.id);
      payloadA =
          '${node('b.example', 'Renamed B')}\n${node('new.example', 'New')}';
      expect(await c.updateSubscription(ids.first), true);
      expect(c.selectedId, selected.id);
      expect(c.selected!.name, 'Renamed B');
      expect(c.profiles.any((p) => p.host == 'a.example'), false);
      payloadA = '<html>subscription error</html>';
      expect(await c.updateSubscription(ids.first), false);
      expect(c.selectedId, selected.id);
      expect(c.subscriptions.first.error, isNotNull);
      await c.removeSubscription(ids.first);
      expect(
        c.profiles.map((p) => p.host),
        containsAll(['manual.example', 'c.example']),
      );
      final reloaded = AppController(
        backend: FakeBackend(),
        store: store,
        platform: 'macos',
      );
      addTearDown(reloaded.dispose);
      await reloaded.initialize(poll: false);
      expect(reloaded.subscriptions, hasLength(1));
      expect(reloaded.profiles, hasLength(2));
    },
  );

  test(
    'subscription UA is persisted, used through redirects, and scoped to subscriptions',
    () async {
      final store = MemoryStore()..value = {};
      const fetch = ResourceFetcher(allowLoopbackHttp: true);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = <String?>[];
      server.listen((r) async {
        received.add(r.headers.value(HttpHeaders.userAgentHeader));
        if (r.uri.path == '/sub') {
          r.response.statusCode = 302;
          r.response.headers.set('location', '/payload');
        } else {
          r.response.write(node('test.example', 'Test'));
        }
        await r.response.close();
      });
      final url = 'http://127.0.0.1:${server.port}';
      final c = AppController(
        backend: FakeBackend(),
        store: store,
        platform: 'windows',
        fetcher: fetch,
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      final id = (await c.addSubscriptions('test', '$url/sub', 0)).single;
      for (final agent in SubscriptionAgent.values) {
        if (agent != SubscriptionAgent.xray) {
          await c.setSubscriptionAgent(agent, 'My Client/2');
        }
        expect(await c.updateSubscription(id), true);
      }
      expect(received, [
        'v2rayN/7.25.6',
        'v2rayN/7.25.6',
        'FlClash/v0.8.96 clash-verge Platform/windows',
        'FlClash/v0.8.96 clash-verge Platform/windows',
        'My Client/2',
        'My Client/2',
      ]);
      await fetch.download('$url/geo', limit: 1024).drain<void>();
      expect(received.last, 'fcxray/0.7.1');
      final restored = AppController(
        backend: FakeBackend(),
        store: store,
        platform: 'windows',
      );
      addTearDown(restored.dispose);
      await restored.initialize(poll: false);
      expect(restored.subscriptionHeader, 'My Client/2');
      await expectLater(
        restored.setSubscriptionAgent(SubscriptionAgent.custom, 'a\r\nb'),
        throwsFormatException,
      );
      await expectLater(
        restored.setSubscriptionAgent(SubscriptionAgent.custom, '  '),
        throwsFormatException,
      );
      await restored.setSubscriptionAgent(SubscriptionAgent.xray, '');
      expect(restored.customSubscriptionAgent, 'My Client/2');
    },
  );

  test(
    'bounded downloads reject overflow, unsafe URLs and preserve redirect limits',
    () async {
      const normal = ResourceFetcher();
      expect(
        () => normal.validateUrl('http://example.com/sub'),
        throwsFormatException,
      );
      expect(
        () => normal.validateUrl('https://user:secret@example.com'),
        throwsFormatException,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((r) async {
        if (r.uri.path == '/loop') {
          r.response.statusCode = 302;
          r.response.headers.set('location', '/loop');
        } else if (r.uri.path == '/redirect') {
          r.response.statusCode = 302;
          r.response.headers.set('location', '/data');
        } else {
          r.response.write('123456789');
        }
        await r.response.close();
      });
      const client = ResourceFetcher(allowLoopbackHttp: true);
      expect(
        await client.subscription('http://127.0.0.1:${server.port}/redirect'),
        '123456789',
      );
      await expectLater(
        client
            .download('http://127.0.0.1:${server.port}/data', limit: 4)
            .drain<void>(),
        throwsFormatException,
      );
      await expectLater(
        client.subscription('http://127.0.0.1:${server.port}/loop'),
        throwsFormatException,
      );
    },
  );

  test(
    'running config is a native snapshot, not a newly generated preview',
    () async {
      final backend = FakeBackend();
      final c = AppController(
        backend: backend,
        store: MemoryStore(),
        platform: 'android',
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      await c.importText(node('a.example', 'A'));
      await c.toggle();
      final running = await c.configuration();
      expect(running['running'], true);
      expect(running['config'], backend.activeConfig);
      await c.toggle();
      final preview = await c.configuration();
      expect(preview['running'], false);
      expect(preview['source'], contains('尚未应用'));
    },
  );

  final helper = File(
    '${Directory.current.path}/native/bin/fcxray-core${Platform.isWindows ? '.exe' : ''}',
  );
  test(
    'geodata import validates protobuf and hash, loads native routing and preserves old version on failure',
    () async {
      final dir = await Directory.systemTemp.createTemp('fcxray-geo-test');
      addTearDown(() => dir.delete(recursive: true));
      final backend = DesktopCoreBackend(executable: helper.path);
      addTearDown(backend.close);
      final geo = GeoStore(backend: backend, directory: dir);
      final ip = await geo.install(
        GeoAsset.defaults('geoip'),
        Stream.value(ipFixture()),
      );
      final site = await geo.install(
        GeoAsset.defaults('geosite'),
        Stream.value(siteFixture()),
      );
      expect(ip.tags, ['cn']);
      expect(site.tags, ['cn']);
      await geo.ensureAvailable([ip, site]);
      await expectLater(
        geo.install(ip, Stream.value(utf8.encode('not protobuf'))),
        throwsStateError,
      );
      final pinned = ip.withSettings(ip.url, List.filled(64, '0').join(), 0);
      await expectLater(
        geo.install(pinned, Stream.value(ipFixture())),
        throwsFormatException,
      );
      expect(
        await File('${dir.path}/${ip.fileName}').readAsBytes(),
        ipFixture(),
      );
      expect(
        await dir.list().where((f) => f.path.contains('.stage-')).length,
        0,
      );
      final config = ConfigBuilder.build(
        ProfileImporter.parse(node('example.com', 'Test')).single,
        platform: 'macos',
        mode: ConnectionMode.proxy,
        routing: RoutingMode.rules,
        useGeo: true,
        geoAssets: {'geoip': ip, 'geosite': site},
      );
      await backend.call('validate', jsonEncode(config), dir.path);
      expect(
        () => ConfigBuilder.build(
          ProfileImporter.parse(node('example.com', 'Test')).single,
          platform: 'macos',
          routing: RoutingMode.rules,
          useGeo: true,
        ),
        throwsFormatException,
      );
    },
    skip: helper.existsSync() ? false : 'Build the native helper first',
  );
}
