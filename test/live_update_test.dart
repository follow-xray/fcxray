import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fcxray/models/resources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcxray/controllers/app_controller.dart';
import 'package:fcxray/services/core_backend.dart';
import 'package:fcxray/services/config_builder.dart';
import 'package:fcxray/services/geo_store.dart';
import 'package:fcxray/services/resource_fetcher.dart';
import 'resources_test.dart' show ipFixture, siteFixture, node;
import 'test_support.dart';

class MutableFetcher extends ResourceFetcher {
  String payload = node('old.example', 'Old');
  Uri? lastProxy;
  Completer<String>? pending;
  @override
  Future<String> subscription(
    String url, {
    String userAgent = SubscriptionAgent.xrayHeader,
    Uri? proxy,
    void Function(DownloadRoute)? onRoute,
  }) async {
    lastProxy = proxy;
    return pending == null ? payload : await pending!.future;
  }
}

class ObservedBackend implements CoreBackend {
  ObservedBackend(this.delegate);
  final CoreBackend delegate;
  final methods = <String>[];
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    String? config,
    String? assetDirectory,
  ]) {
    methods.add(method);
    return delegate.call(method, config, assetDirectory);
  }

  @override
  Future<void> close() => delegate.close();
}

Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  test(
    'connected subscription replacement freezes active node and takes effect only on explicit reconnect',
    () async {
      final fetch = MutableFetcher(), backend = ObservedBackend(FakeBackend());
      final store = MemoryStore();
      final c = AppController(
        backend: backend,
        store: store,
        platform: 'android',
        fetcher: fetch,
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      final id = (await c.addSubscriptions(
        'Sub',
        'https://example.com/sub',
        0,
      )).single;
      await c.updateSubscription(id);
      await c.toggle();
      final original = (await c.configuration())['config'];
      final marker = backend.methods.length;
      fetch.payload = node('new.example', 'New');
      await c.updateSubscription(id);
      expect(fetch.lastProxy?.port, 10809);
      expect(c.selected!.host, 'new.example');
      expect(c.activeProfile!.host, 'old.example');
      expect((await c.configuration())['config'], original);
      expect(c.pendingChanges, true);
      expect(c.connected, true);
      expect(backend.methods.skip(marker), isNot(contains('start')));
      expect(backend.methods.skip(marker), isNot(contains('stop')));
      expect(backend.methods.skip(marker), isNot(contains('validate')));
      // Reopening Android UI reads the real running snapshot, not new stored nodes.
      final reopened = AppController(
        backend: backend,
        store: store,
        platform: 'android',
        fetcher: fetch,
      );
      addTearDown(reopened.dispose);
      await reopened.initialize(poll: false);
      await reopened.refresh();
      expect(reopened.activeProfile!.host, 'old.example');
      expect(reopened.selected!.host, 'new.example');
      await c.toggle();
      await c.toggle();
      expect(c.activeProfile!.host, 'new.example');
      expect(c.pendingChanges, false);
    },
  );
  test(
    'disconnect remains available during a resource download and deleting the last subscription',
    () async {
      final fetch = MutableFetcher();
      final c = AppController(
        backend: FakeBackend(),
        store: MemoryStore(),
        platform: 'android',
        fetcher: fetch,
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      final id = (await c.addSubscriptions(
        'Sub',
        'https://example.com/sub',
        0,
      )).single;
      await c.updateSubscription(id);
      await c.toggle();
      fetch.pending = Completer<String>();
      final update = c.updateSubscription(id);
      await Future<void>.delayed(Duration.zero);
      expect(c.saving, true);
      expect(c.canToggle, true);
      await c.toggle();
      expect(c.connected, false);
      fetch.pending!.complete(node('new.example', 'New'));
      await update;
      expect(c.selected!.host, 'new.example');
      fetch.pending = null;
      await c.toggle();
      await c.removeSubscription(id);
      expect(c.selected, isNull);
      expect(c.activeProfile, isNotNull);
      expect(c.canToggle, true);
      await c.toggle();
      expect(c.connected, false);
    },
  );
  test(
    'proxy priority and fallback retry the full resource without joining partial bytes',
    () async {
      final direct = await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
          proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => direct.close(force: true));
      addTearDown(() => proxy.close(force: true));
      var directHits = 0, proxyHits = 0, broken = false;
      final headers = <String?>[];
      direct.listen((r) async {
        headers.add(r.headers.value(HttpHeaders.userAgentHeader));
        directHits++;
        r.response.write('complete-direct');
        await r.response.close();
      });
      proxy.listen((r) async {
        headers.add(r.headers.value(HttpHeaders.userAgentHeader));
        proxyHits++;
        if (!broken) {
          r.response.write('complete-proxy');
          await r.response.close();
        } else {
          final socket = await r.response.detachSocket(writeHeaders: false);
          socket.write(
            'HTTP/1.1 200 OK\r\nContent-Length: 100\r\nConnection: close\r\n\r\npartial-',
          );
          await socket.flush();
          socket.destroy();
        }
      });
      const fetch = ResourceFetcher(allowLoopbackHttp: true);
      final route = Uri(scheme: 'http', host: '127.0.0.1', port: proxy.port),
          url = 'http://127.0.0.1:${direct.port}/file';
      expect(await fetch.subscription(url, proxy: route), 'complete-proxy');
      expect(proxyHits, 1);
      expect(directHits, 0);
      broken = true;
      expect(
        await fetch.subscription(url, proxy: route, userAgent: 'Custom/2'),
        'complete-direct',
      );
      expect(headers, [SubscriptionAgent.xrayHeader, 'Custom/2', 'Custom/2']);
      expect(proxyHits, 2);
      expect(directHits, 1);
    },
  );
  final helper = File(
    'native/bin/fcxray-core${Platform.isWindows ? '.exe' : ''}',
  );
  test(
    'real core keeps session, traffic and Geo files intact while subscription and Geo update through it',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fcxray-live-update-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var subscription = jsonEncode({
        'tag': 'Original',
        'protocol': 'freedom',
        'settings': {'targetStrategy': 'AsIs'},
      });
      var database = ipFixture();
      server.listen((r) async {
        if (r.uri.path == '/sub') {
          r.response.write(subscription);
        } else if (r.uri.path == '/geo') {
          r.response.add(database);
        } else {
          r.response.write('still-connected');
        }
        await r.response.close();
      });
      final backend = ObservedBackend(
        DesktopCoreBackend(executable: helper.absolute.path),
      );
      final c = AppController(
        backend: backend,
        store: MemoryStore(),
        platform: 'macos',
        fetcher: const ResourceFetcher(allowLoopbackHttp: true),
        geoStore: GeoStore(backend: backend, directory: directory),
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      final sub = (await c.addSubscriptions(
        'Local',
        'http://127.0.0.1:${server.port}/sub',
        0,
      )).single;
      await c.updateSubscription(sub);
      await c.importGeo('geoip', Stream.value(ipFixture()));
      await c.importGeo('geosite', Stream.value(siteFixture()));
      await c.configureGeo(
        c.geoAssets['geoip']!.withSettings(
          'http://127.0.0.1:${server.port}/geo',
          '',
          0,
        ),
      );
      await c.ruleOptions(geo: true);
      await c.settings(ConnectionMode.proxy, RoutingMode.rules);
      final originalFile = c.geoAssets['geoip']!.fileName!;
      final socks = await freePort(), http = await freePort();
      final startConfig = c.buildConfig();
      (startConfig['inbounds'] as List)[0]['port'] = socks;
      (startConfig['inbounds'] as List)[1]['port'] = http;
      await backend.call('start', jsonEncode(startConfig), directory.path);
      await c.refresh();
      final before = await backend.call('config');
      final marker = backend.methods.length;
      subscription = jsonEncode({
        'tag': 'Next',
        'protocol': 'freedom',
        'settings': {'targetStrategy': 'UseIPv4'},
      });
      database = [...ipFixture()];
      final index = database.indexOf(192);
      database[index] = 198;
      expect(await c.updateSubscription(sub), true);
      expect(await c.updateGeo('geoip'), true);
      final after = await backend.call('config');
      expect(after['sessionId'], before['sessionId']);
      expect(after['config'], before['config']);
      expect(c.connected, true);
      expect(c.geoAssets['geoip']!.fileName, isNot(originalFile));
      expect(
        await File('${directory.path}/$originalFile').readAsBytes(),
        ipFixture(),
      );
      expect(c.activeProfile!.name, 'Original');
      expect(c.selected!.name, 'Next');
      expect(backend.methods.skip(marker), isNot(contains('start')));
      expect(backend.methods.skip(marker), isNot(contains('stop')));
      expect(backend.methods.skip(marker), isNot(contains('validate')));
      final text = await const ResourceFetcher(allowLoopbackHttp: true)
          .subscription(
            'http://127.0.0.1:${server.port}/echo',
            proxy: Uri(scheme: 'http', host: '127.0.0.1', port: http),
          );
      expect(text, 'still-connected');
      final stats = await backend.call('status');
      expect(stats['upload'] as num, greaterThan(0));
      expect(stats['download'] as num, greaterThan(0));
      final upcoming = await c.previewConfiguration();
      expect(
        upcoming['config'] as String,
        contains(c.geoAssets['geoip']!.fileName!),
      );
      await backend.call('stop');
      final next = c.buildConfig();
      (next['inbounds'] as List)[0]['port'] = socks;
      (next['inbounds'] as List)[1]['port'] = http;
      await backend.call('start', jsonEncode(next), directory.path);
      await c.refresh();
      expect(c.activeProfile!.name, 'Next');
      final newSession = await backend.call('config');
      expect(newSession['sessionId'], isNot(before['sessionId']));
      expect(
        newSession['config'] as String,
        contains(c.geoAssets['geoip']!.fileName!),
      );
    },
    skip: helper.existsSync() ? false : 'Build native helper first',
  );
}
