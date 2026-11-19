import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcxray/services/profile_importer.dart';
import 'package:fcxray/services/config_builder.dart';

const link =
    'vless://11111111-1111-4111-8111-111111111111@example.com:443?security=tls&type=ws&path=%2Fx&host=cdn.example.com#Tokyo';

void main() {
  test('VLESS imports encoded websocket and TLS parameters', () {
    final p = ProfileImporter.parse(link).single;
    expect(p.name, 'Tokyo');
    expect(p.host, 'example.com');
    expect(p.port, 443);
    expect(p.outbound['streamSettings']['wsSettings']['path'], '/x');
    expect(
      p.outbound['streamSettings']['tlsSettings'].containsKey('allowInsecure'),
      false,
    );
  });
  test('IPv6, Trojan password and REALITY fields survive parsing', () {
    final t = ProfileImporter.parse(
      'trojan://a%40b%3Ac@[2001:db8::1]:443?sni=example.com',
    ).single;
    expect(t.host, '2001:db8::1');
    expect(t.outbound['settings']['servers'][0]['password'], 'a@b:c');
    final p = ProfileImporter.parse(
      '${link.split('?').first}?security=reality&pbk=test&sid=ab&sni=example.com',
    ).single;
    expect(p.outbound['streamSettings']['realitySettings']['shortId'], 'ab');
  });
  test('VMess and both SIP002 Shadowsocks encodings', () {
    final vmess = base64Encode(
      utf8.encode(
        jsonEncode({
          'v': '2',
          'ps': 'VMess',
          'add': 'example.com',
          'port': '443',
          'id': '11111111-1111-4111-8111-111111111111',
          'aid': '0',
          'net': 'tcp',
          'tls': 'tls',
        }),
      ),
    );
    expect(ProfileImporter.parse('vmess://$vmess').single.protocol, 'vmess');
    final auth = base64Url
        .encode(utf8.encode('aes-128-gcm:pass:word'))
        .replaceAll('=', '');
    final full = base64Encode(
      utf8.encode('aes-128-gcm:pass:word@example.com:8388'),
    );
    for (final value in ['ss://$auth@example.com:8388#SS', 'ss://$full#SS']) {
      expect(
        ProfileImporter.parse(
          value,
        ).single.outbound['settings']['servers'][0]['password'],
        'pass:word',
      );
    }
  });
  test(
    'batch and pasted base64 subscriptions are atomic and errors hide secrets',
    () {
      final subscription = base64Encode(utf8.encode('$link\n$link'));
      expect(ProfileImporter.parse(subscription), hasLength(2));
      expect(
        () => ProfileImporter.parse('$link\nnot-a-secret'),
        throwsFormatException,
      );
      expect(
        () => ProfileImporter.parse('trojan://supersecret@example.com'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'no credential',
            isNot(contains('supersecret')),
          ),
        ),
      );
      expect(
        () => ProfileImporter.parse('$link&allowInsecure=1'),
        returnsNormally,
      ); // fragment, not query
      expect(
        () => ProfileImporter.parse(
          link.replaceFirst('#Tokyo', '&allowInsecure=1'),
        ),
        throwsFormatException,
      );
    },
  );
  test('full JSON imports proxy outbounds and rejects dependent chains', () {
    final outbound = ProfileImporter.parse(link).single.outbound;
    expect(
      ProfileImporter.parse(
        jsonEncode({
          'outbounds': [
            outbound,
            {'protocol': 'freedom'},
          ],
        }),
      ),
      hasLength(1),
    );
    expect(
      () => ProfileImporter.parse(
        jsonEncode({
          ...outbound,
          'proxySettings': {'tag': 'other'},
        }),
      ),
      throwsFormatException,
    );
  });
  test('TUN routes, Android FD ownership and local-only proxies', () {
    final p = ProfileImporter.parse(link).single;
    for (final platform in ['android', 'windows', 'macos']) {
      final config = ConfigBuilder.build(p, platform: platform);
      final tun = (config['inbounds'] as List).first['settings'] as Map;
      expect(tun.containsKey('autoOutboundsInterface'), platform != 'android');
      if (platform == 'windows') {
        expect(tun['autoSystemWfpBlockLeak'], contains('dns'));
      }
      expect(config['routing']['rules'][0]['outboundTag'], 'dns-out');
      expect(config['outbounds'][0]['tag'], 'proxy');
      for (final inbound in (config['inbounds'] as List).skip(1)) {
        expect(inbound['listen'], '127.0.0.1');
      }
    }
    final proxy = ConfigBuilder.build(
      p,
      platform: 'macos',
      mode: ConnectionMode.proxy,
    );
    expect(
      (proxy['inbounds'] as List).any((e) => e['protocol'] == 'tun'),
      false,
    );
  });
}
