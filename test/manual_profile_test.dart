import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcxray/services/manual_profile.dart';
import 'package:fcxray/services/config_builder.dart';
import 'package:fcxray/services/core_backend.dart';
import 'package:fcxray/models/profile.dart';
import 'package:fcxray/ui/config_viewer.dart';

Map<String, String> values(String protocol) => {
  ...ManualProfile.fields(),
  'name': 'Manual $protocol',
  'protocol': protocol,
  'address': 'example.com',
  'port': '443',
  'credential': ['vless', 'vmess'].contains(protocol)
      ? '11111111-1111-4111-8111-111111111111'
      : 'pass:word',
  'security': protocol == 'trojan' ? 'tls' : 'none',
};

void main() {
  test(
    'four manual protocols generate usable credentials and preserve advanced settings on edit',
    () {
      for (final protocol in ManualProfile.basicProtocols) {
        final p = ManualProfile.build(values(protocol));
        expect(p.protocol, protocol);
        expect(p.host, 'example.com');
        expect(p.port, 443);
        final advanced = Profile(
          id: p.id,
          name: p.name,
          outbound: {
            ...p.outbound,
            'streamSettings': {
              ...p.outbound['streamSettings'] as Map,
              'sockopt': {'tcpKeepAliveIdle': 45},
            },
          },
        );
        final edited = ManualProfile.build({
          ...ManualProfile.fields(advanced),
          'name': 'Edited',
        }, original: advanced);
        expect(
          edited.outbound['streamSettings']['sockopt']['tcpKeepAliveIdle'],
          45,
        );
      }
      expect(
        () => ManualProfile.build({...values('vless'), 'port': '0'}),
        throwsFormatException,
      );
      expect(
        () => ManualProfile.build({
          ...values('vless'),
          'flow': 'xtls-rprx-vision',
          'mux': 'true',
          'security': 'tls',
        }),
        throwsFormatException,
      );
    },
  );
  test('configuration masking does not mutate actual secrets', () {
    final original = {
      'settings': {'id': 'secret-id', 'password': 'secret-password'},
      'streamSettings': {
        'tlsSettings': {'serverName': 'example.com'},
      },
    };
    final masked = redactConfig(original) as Map;
    expect(masked['settings']['id'], '••••••');
    expect(masked['settings']['password'], '••••••');
    expect(original['settings']!['password'], 'secret-password');
  });
  final helper = File(
    '${Directory.current.path}/native/bin/fcxray-core${Platform.isWindows ? '.exe' : ''}',
  );
  test(
    'every manual protocol and transport passes the real core configuration parser',
    () async {
      final backend = DesktopCoreBackend(executable: helper.path);
      addTearDown(backend.close);
      for (final protocol in ManualProfile.basicProtocols) {
        for (final network in [
          'tcp',
          'raw',
          'ws',
          'grpc',
          'xhttp',
          'httpupgrade',
        ]) {
          final p = ManualProfile.build({
            ...values(protocol),
            'network': network,
            'security': 'tls',
            'sni': 'example.com',
            'serviceName': 'service',
          });
          await backend.call(
            'validate',
            jsonEncode(
              ConfigBuilder.build(
                p,
                platform: 'macos',
                mode: ConnectionMode.proxy,
              ),
            ),
          );
        }
      }
      final reality = ManualProfile.build({
        ...values('vless'),
        'security': 'reality',
        'sni': 'example.com',
        'shortId': 'ab',
        'publicKey': base64UrlEncode(
          List.generate(32, (i) => i + 1),
        ).replaceAll('=', ''),
      });
      await backend.call(
        'validate',
        jsonEncode(
          ConfigBuilder.build(
            reality,
            platform: 'macos',
            mode: ConnectionMode.proxy,
          ),
        ),
      );
    },
    skip: helper.existsSync() ? false : 'Build the native helper first',
  );
}
