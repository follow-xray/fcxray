import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fcxray/controllers/app_controller.dart';
import 'package:fcxray/models/route_override.dart';
import 'package:fcxray/services/config_builder.dart';
import 'package:fcxray/services/core_backend.dart';
import 'package:fcxray/services/desktop_tray.dart';
import 'package:fcxray/services/profile_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_support.dart';

class _FailOnce extends FakeBackend {
  bool rejectStart = false;
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    String? config,
    String? assets,
  ]) {
    if (method == 'start' && rejectStart) {
      rejectStart = false;
      throw StateError('start failed');
    }
    return super.call(method, config, assets);
  }
}

void main() {
  final node = ProfileImporter.parse('trojan://test@example.com:443#A').single;
  test(
    'failed live node switch restores the running snapshot and saved selection',
    () async {
      final backend = _FailOnce(), store = MemoryStore();
      final c = AppController(
        backend: backend,
        store: store,
        platform: 'windows',
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      await c.importText(
        'trojan://p@one.example:443#One\ntrojan://p@two.example:443#Two',
      );
      final old = c.selectedId, next = c.profiles.last.id;
      await c.toggle();
      final running = backend.activeConfig;
      backend.rejectStart = true;
      await c.switchNode(next);
      expect(c.connected, true);
      expect(backend.activeConfig, running);
      expect(c.activeProfile?.id, old);
      expect(store.value!['selectedId'], old);
      store.fail = true;
      await c.switchNode(next);
      expect(c.selectedId, old);
      expect(c.connected, true);
      expect(backend.activeConfig, running);
      expect(c.error, isNotNull);
      store.fail = false;
      await c.switchNode(next);
      expect(backend.activeConfig, isNot(running));
      expect(store.value!['selectedId'], next);
    },
  );
  test('imports old modes and round-trips user preferences', () async {
    for (final old in ['global', 'bypassLan', 'geoRules']) {
      final store = MemoryStore()..value = {'routing': old};
      final c = AppController(
        backend: FakeBackend(),
        store: store,
        platform: 'android',
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      expect(
        c.routing,
        old == 'global' ? RoutingMode.global : RoutingMode.rules,
      );
      expect(c.useGeo, old == 'geoRules');
      expect(c.bypassLan, true);
      final override = RouteOverride.parse(
        TargetKind.ip,
        '192.168.1.80/24',
        RouteAction.proxy,
      );
      await c.saveOverrides([override]);
      expect(store.value!['routeOverrides'][0]['target'], '192.168.1.0/24');
      await expectLater(
        c.saveOverrides([override, override]),
        throwsFormatException,
      );
      expect(c.overrides, hasLength(1));
      final restored = AppController(
        backend: FakeBackend(),
        store: store,
        platform: 'android',
      );
      addTearDown(restored.dispose);
      await restored.initialize(poll: false);
      expect(restored.overrides.single.action, RouteAction.proxy);
    }
  });
  test('mode boundaries and custom matcher order', () {
    final overrides = [
      RouteOverride.parse(
        TargetKind.exact,
        'Pay.Example.COM.',
        RouteAction.proxy,
      ),
      RouteOverride.parse(TargetKind.domain, 'example.com', RouteAction.block),
      RouteOverride.parse(TargetKind.ip, '2001:db8::3/64', RouteAction.direct),
      RouteOverride.parse(
        TargetKind.ip,
        '192.168.1.4',
        RouteAction.proxy,
        enabled: false,
      ),
    ];
    for (final mode in RoutingMode.values) {
      final cfg = ConfigBuilder.build(
        mode == RoutingMode.direct ? null : node,
        platform: 'android',
        routing: mode,
        overrides: overrides,
      );
      final tun = cfg['inbounds'][0]['settings'];
      expect(tun['name'], 'fcxray');
      expect(tun.containsKey('autoOutboundsInterface'), false);
      final rules = cfg['routing']['rules'] as List;
      expect(rules.first['outboundTag'], 'dns-out');
      expect(
        cfg['outbounds'][0]['tag'],
        mode == RoutingMode.direct ? 'direct' : 'proxy',
      );
      if (mode == RoutingMode.rules) {
        expect(rules[1]['domain'], ['full:pay.example.com']);
        expect(rules[2]['domain'], ['domain:example.com']);
        expect(rules[2]['outboundTag'], 'block');
        expect(rules[3]['ip'], ['2001:db8::/64']);
        expect(rules.length, 5);
      } else {
        expect(rules.length, 1);
      }
    }
    for (final bad in [
      '::1/129',
      '127.0.0.1/33',
      'foo:123',
      'https://example.com',
    ]) {
      expect(
        () => RouteOverride.parse(TargetKind.ip, bad, RouteAction.direct),
        throwsFormatException,
      );
    }
  });
  test(
    'tray live switch rolls back identical session config on start or persistence failure',
    () async {
      final backend = _FailOnce();
      final store = MemoryStore();
      final c = AppController(
        backend: backend,
        store: store,
        platform: 'windows',
      );
      addTearDown(c.dispose);
      await c.initialize(poll: false);
      final tray = DesktopTray(c);
      await tray.handle('routing/direct');
      expect(c.canToggle, true);
      await c.toggle();
      expect(c.connected, true);
      expect(c.activeProfile!.protocol, 'freedom');
      await c.toggle();
      await c.importText('trojan://test@example.com:443#A');
      await c.toggle();
      await tray.handle('routing/global');
      expect(c.connected, true);
      expect(c.activeProfile!.name, 'A');
      expect(c.routing, RoutingMode.global);
      expect(tray.buildMenu().getMenuItem('routing/global')!.checked, true);
      final original = backend.activeConfig;
      backend.rejectStart = true;
      await c.switchRouting(RoutingMode.rules);
      expect(backend.activeConfig, original);
      expect(c.connected, true);
      expect(c.routing, RoutingMode.global);
      expect(c.error, isNotNull);
      store.fail = true;
      await c.switchRouting(RoutingMode.rules);
      expect(backend.activeConfig, original);
      expect(c.routing, RoutingMode.global);
      store.fail = false;
      await c.switchRouting(RoutingMode.rules);
      expect(c.routing, RoutingMode.rules);
      expect(c.connected, true);
      final active = backend.activeConfig;
      await c.saveOverrides([
        RouteOverride.parse(
          TargetKind.domain,
          'example.com',
          RouteAction.block,
        ),
      ]);
      expect(c.pendingChanges, true);
      expect(backend.activeConfig, active);
    },
  );
  test(
    'native Xray applies domain/IP actions ahead of LAN bypass',
    () async {
      final backend = DesktopCoreBackend();
      addTearDown(backend.close);
      final destination = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => destination.close(force: true));
      final received = Completer<void>();
      final release = Completer<void>();
      destination.listen((r) async {
        if (r.uri.path == '/hold') {
          received.complete();
          await release.future;
        }
        r.response.write('direct');
        r.response.close();
      });
      final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(proxy.close);
      var upstreamHits = 0;
      proxy.listen((sock) async {
        var input = '';
        var connected = false;
        try {
          await for (final chunk in sock) {
            input += latin1.decode(chunk);
            final end = input.indexOf('\r\n\r\n');
            if (end < 0) continue;
            if (!connected) {
              expect(input, startsWith('CONNECT '));
              upstreamHits++;
              sock.write('HTTP/1.1 200 Connection Established\r\n\r\n');
              await sock.flush();
              connected = true;
              input = input.substring(end + 4);
            }
            if (!input.contains('\r\n\r\n')) continue;
            sock.write(
              'HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nproxy',
            );
            await sock.flush();
            break;
          }
        } finally {
          sock.destroy();
        }
      });
      final outbound = ProfileImporter.parse(
        'http://127.0.0.1:${proxy.port}',
      ).single;
      final portReservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = portReservation.port;
      await portReservation.close();
      final cfg = ConfigBuilder.build(
        outbound,
        platform: 'macos',
        mode: ConnectionMode.proxy,
        overrides: [
          RouteOverride.parse(
            TargetKind.exact,
            'localhost',
            RouteAction.direct,
          ),
          RouteOverride.parse(
            TargetKind.domain,
            'blocked.example',
            RouteAction.block,
          ),
          RouteOverride.parse(TargetKind.ip, '127.0.0.1', RouteAction.proxy),
        ],
      );
      cfg['inbounds'] = [
        {
          'tag': 'http-in',
          'protocol': 'http',
          'listen': '127.0.0.1',
          'port': port,
        },
      ];
      await backend.call('start', jsonEncode(cfg));
      Future<String> get(String host, [String path = '/']) async {
        final client = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:$port';
        try {
          final r = await client.getUrl(
            Uri.parse('http://$host:${destination.port}$path'),
          );
          final response = await r.close().timeout(const Duration(seconds: 3));
          return await response
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 3));
        } finally {
          client.close(force: true);
        }
      }

      expect(await get('localhost'), 'direct');
      expect(upstreamHits, 0);
      expect(await get('127.0.0.1'), 'proxy');
      expect(upstreamHits, 1);
      String? blocked;
      try {
        blocked = await get('child.blocked.example');
      } on Exception {
        /* blocked before response */
      }
      expect(blocked, isNot('proxy'));
      expect(blocked, isNot('direct'));
      expect(upstreamHits, 1);
      final held = get('localhost', '/hold');
      await received.future.timeout(const Duration(seconds: 3));
      final before = await backend.call('config');
      final controller = AppController(
        backend: backend,
        store: MemoryStore(),
        platform: 'macos',
      );
      await controller.initialize(poll: false);
      await controller.importText('http://127.0.0.1:65534#Next');
      await controller.settings(ConnectionMode.proxy, RoutingMode.rules);
      await controller.refresh();
      try {
        await controller.saveOverrides([
          RouteOverride.parse(TargetKind.exact, 'localhost', RouteAction.proxy),
        ]);
        await controller.applyRulesNow();
      } finally {
        release.complete();
      }
      expect(await held, 'direct');
      expect(await get('localhost'), 'proxy');
      final after = await backend.call('config');
      expect(after['sessionId'], before['sessionId']);
      final live = jsonDecode(after['config']);
      expect(live['outbounds'], cfg['outbounds']);
      expect(live['inbounds'], cfg['inbounds']);
      await expectLater(
        backend.call(
          'applyRules',
          jsonEncode({'session': 'expired', 'config': after['config']}),
        ),
        throwsStateError,
      );
      final bad = {
        ...live,
        'routing': {
          ...live['routing'] as Map,
          'rules': [
            {
              'type': 'field',
              'ip': ['invalid-address'],
              'outboundTag': 'block',
            },
          ],
        },
      };
      await expectLater(
        backend.call(
          'applyRules',
          jsonEncode({
            'session': after['sessionId'],
            'config': jsonEncode(bad),
          }),
        ),
        throwsStateError,
      );
      expect(await backend.call('config'), after);
    },
    skip: !File(
      'native/bin/fcxray-core${Platform.isWindows ? '.exe' : ''}',
    ).existsSync(),
  );
}
