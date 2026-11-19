import 'dart:convert';
import 'dart:io';
import 'package:fcxray/services/manual_profile.dart';
import 'package:fcxray/services/protocol_catalog.dart';
import 'package:fcxray/services/protocol_fields.dart';
import 'package:fcxray/services/config_builder.dart';

Map<String, String> validFields(String protocol, {String? network}) {
  final values = {
    ...ManualProfile.fields(),
    'name': 'Fixture $protocol',
    'protocol': protocol,
    'address': 'example.com',
    'port': '443',
    'credential': ['vless', 'vmess'].contains(protocol)
        ? '11111111-1111-4111-8111-111111111111'
        : 'test-password',
    'network': network ?? ProtocolFields.defaultNetwork(protocol),
    'security': protocol == 'vless'
        ? 'tls'
        : ProtocolFields.defaultSecurity(protocol),
    'wgKey': base64Encode(List.generate(32, (i) => i + 1)),
    'wgPeerKey': base64Encode(List.generate(32, (i) => i + 2)),
    'wgEndpoint': 'example.com:51820',
    'hyAuth': 'test-auth',
    'proxyUser': 'test-user',
    'proxyPass': 'test-pass',
    'mqUser': 'test-user',
    'mqPass': 'test-pass',
  };
  if (['hysteria', 'masque'].contains(values['network'])) {
    values['security'] = 'tls';
  }
  if (values['network'] == 'kcp') {
    values['security'] = 'none';
    values['encryption'] =
        'mlkem768x25519plus.native.0rtt.${base64UrlEncode(List.generate(32, (i) => i + 1)).replaceAll('=', '')}';
  }
  if (values['network'] == 'xdrive') {
    values.addAll({
      'encryption':
          'mlkem768x25519plus.native.0rtt.${base64UrlEncode(List.generate(32, (i) => i + 1)).replaceAll('=', '')}',
      'mux': 'true',
      'concurrency': '128',
      'flow': '',
      'xdService': 'local',
      'xdFolder': '/tmp/fcxray-fixture',
      'security': 'none',
    });
  }
  return values;
}

Map<String, Map<String, dynamic>> protocolFixtures() {
  final result = <String, Map<String, dynamic>>{};
  void add(String name, Map<String, String> values) {
    result[name] = ConfigBuilder.build(
      ManualProfile.build(values),
      platform: 'macos',
      mode: ConnectionMode.proxy,
    );
  }

  for (final protocol in ProtocolCatalog.protocols) {
    add(protocol, validFields(protocol));
  }
  for (final network in ProtocolCatalog.networks) {
    final protocol = network == 'masque' ? 'masque' : 'vless';
    add('$protocol/$network', validFields(protocol, network: network));
  }
  for (final cipher in ManualProfile.ciphers.where(
    (c) => c.startsWith('2022-'),
  )) {
    add(cipher, {
      ...validFields('shadowsocks'),
      'method': cipher,
      'credential': base64Encode(
        List.filled(cipher.contains('aes-128') ? 16 : 32, 7),
      ),
    });
  }
  for (final provider in ['google-drive', 's3', 'template']) {
    add('xdrive/$provider', {
      ...validFields('vless', network: 'xdrive'),
      'xdService': provider,
      'xdFolder': 'fcxray-test',
      'xdSecrets': provider == 'google-drive'
          ? '["client-id","client-secret","refresh-token"]'
          : '["access-key","secret-key"]',
      'xdS3':
          '{"endpoint":"https://s3.example.com","region":"us-east-1","bucket":"fcxray","pathStyle":true}',
      'xdTemplate': jsonEncode({
        'flatten': true,
        'auth': {
          'type': 'basic',
          'username': '{secret0}',
          'password': '{secret1}',
        },
        'put': {'method': 'PUT', 'url': 'https://dav.example/{folder}/{name}'},
        'get': {'method': 'GET', 'url': 'https://dav.example/{folder}/{name}'},
        'delete': {
          'method': 'DELETE',
          'url': 'https://dav.example/{folder}/{name}',
        },
        'list': {
          'method': 'PROPFIND',
          'url': 'https://dav.example/{folder}/',
          'namesRegex': '<href>([^<]+)</href>',
        },
      }),
    });
  }
  return result;
}

void main() => stdout.writeln(
  jsonEncode({
    'protocols': ProtocolCatalog.protocols,
    'aliases': ProtocolCatalog.aliases,
    'networks': ProtocolCatalog.networks,
    'cases': protocolFixtures(),
  }),
);
