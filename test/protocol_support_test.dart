import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcxray/services/core_backend.dart';
import 'package:fcxray/services/manual_profile.dart';
import 'package:fcxray/services/profile_importer.dart';
import 'package:fcxray/services/protocol_catalog.dart';
import 'package:fcxray/ui/config_viewer.dart';
import '../tool/protocol_fixtures.dart';

void main() {
  test(
    'catalog covers the pinned native outbound registry including aliases',
    () {
      final source = File(
        'third_party/Xray-core/infra/conf/xray.go',
      ).readAsStringSync();
      final block = source
          .split('outboundConfigLoader =')
          .last
          .split('}, "protocol", "settings")')
          .first;
      final names = RegExp(
        r'"([a-z-]+)":\s+func',
      ).allMatches(block).map((m) => m.group(1)!).toSet();
      expect({
        ...ProtocolCatalog.protocols,
        ...ProtocolCatalog.aliases.keys,
      }, names);
    },
  );
  test(
    'all outbound models import and render endpoints, including flat native configs',
    () {
      for (final entry in protocolFixtures().entries) {
        final out = (entry.value['outbounds'] as List).first;
        final p = ProfileImporter.parse(jsonEncode(out)).single;
        expect(p.host, isNotEmpty, reason: entry.key);
        expect(p.endpointLabel, isNotEmpty);
        final fields = ManualProfile.fields(p);
        expect(fields['protocol'], p.protocol);
        final edited = ManualProfile.build({
          ...fields,
          'name': 'Edited',
        }, original: p);
        expect(edited.protocol, p.protocol);
      }
      for (final alias in ['direct', 'block']) {
        expect(
          ProfileImporter.parse(
            jsonEncode({'protocol': alias, 'settings': {}}),
          ).single.isUtility,
          true,
        );
      }
    },
  );
  test(
    'xdrive requires encrypted VLESS plus mux and accepts all four storage providers',
    () {
      final fields = validFields('vless', network: 'xdrive');
      expect(
        () => ManualProfile.build({...fields, 'encryption': 'none'}),
        throwsFormatException,
      );
      expect(
        () => ManualProfile.build({...fields, 'mux': 'false'}),
        throwsFormatException,
      );
      expect(
        () => ManualProfile.build({...fields, 'flow': 'xtls-rprx-vision'}),
        throwsFormatException,
      );
      final p = ManualProfile.build(fields);
      expect(
        p.outbound['streamSettings']['xdriveSettings']['service'],
        'local',
      );
      final uri = Uri(
        scheme: 'vless',
        userInfo: fields['credential'],
        host: 'example.com',
        port: 443,
        queryParameters: {
          'type': 'xdrive',
          'encryption': fields['encryption']!,
          'xdriveSettings': jsonEncode({
            'service': 'local',
            'remoteFolder': '/tmp/fcxray-test',
          }),
        },
      );
      expect(
        ProfileImporter.parse(uri.toString()).single.outbound['mux']['enabled'],
        true,
      );
    },
  );
  test('HTTP, SOCKS5, Hysteria2, WireGuard and MASQUE links import', () {
    final cases = {
      'https://user:pass@example.com:443': 'http',
      'socks5://user:pass@example.com:1080': 'socks',
      'hy2://secret@example.com:443?sni=example.com&obfs=salamander&obfs-password=mask':
          'hysteria',
      'wireguard://${Uri.encodeComponent(base64Encode(List.filled(32, 1)))}@example.com:51820?publickey=${Uri.encodeComponent(base64Encode(List.filled(32, 2)))}':
          'wireguard',
      'masque://user:pass@example.com:443': 'masque',
    };
    for (final entry in cases.entries) {
      expect(ProfileImporter.parse(entry.key).single.protocol, entry.value);
    }
  });
  test('new protocol secrets are redacted recursively', () {
    final masked =
        redactConfig({
              'settings': {
                'secretKey': 'private',
                'peers': [
                  {'preSharedKey': 'psk'},
                ],
              },
              'streamSettings': {
                'xdriveSettings': {
                  'secrets': ['a', 'b', 'c'],
                },
                'hysteriaSettings': {'auth': 'token'},
              },
            })
            as Map;
    expect(masked['settings']['secretKey'], '••••••');
    expect(masked['streamSettings']['xdriveSettings']['secrets'], '••••••');
    expect(masked['streamSettings']['hysteriaSettings']['auth'], '••••••');
  });
  final helper = File(
    'native/bin/fcxray-core${Platform.isWindows ? '.exe' : ''}',
  );
  test(
    'native parser validates every protocol, transport, SS2022 cipher and xdrive provider',
    () async {
      final backend = DesktopCoreBackend(executable: helper.absolute.path);
      addTearDown(backend.close);
      final failures = <String>[];
      for (final entry in protocolFixtures().entries) {
        try {
          await backend.call('validate', jsonEncode(entry.value));
        } on Object catch (e) {
          failures.add('${entry.key}: $e');
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    },
    skip: helper.existsSync() ? false : 'Build native helper first',
  );
}
