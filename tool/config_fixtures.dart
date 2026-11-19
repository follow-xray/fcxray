import 'dart:convert';
import 'dart:io';
import 'package:fcxray/services/config_builder.dart';
import 'package:fcxray/services/profile_importer.dart';

void main() {
  final p = ProfileImporter.parse(
    'vless://11111111-1111-4111-8111-111111111111@127.0.0.1:19090?security=none#Local-test',
  ).single;
  stdout.writeln(
    jsonEncode({
      for (final platform in ['android', 'windows', 'macos'])
        platform: ConfigBuilder.build(p, platform: platform),
      'proxy': ConfigBuilder.build(
        p,
        platform: 'macos',
        mode: ConnectionMode.proxy,
        routing: RoutingMode.global,
      ),
    }),
  );
}
