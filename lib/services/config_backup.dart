import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

class ConfigBackup {
  const ConfigBackup(this.savedAt, this.state);
  final DateTime savedAt;
  final Map<String, dynamic> state;

  Map<String, dynamic> toJson() => {
    'format': 'fcxray.config-backup',
    'version': 1,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'state': state,
    'sha256': sha256.convert(utf8.encode(jsonEncode(state))).toString(),
  };

  factory ConfigBackup.fromJson(Map<String, dynamic> json) {
    final state = json['state'];
    final time = DateTime.tryParse('${json['savedAt']}');
    if (json['format'] != 'fcxray.config-backup' ||
        json['version'] != 1 ||
        state is! Map<String, dynamic> ||
        state['profiles'] is! List ||
        state['subscriptions'] is! List ||
        time == null ||
        sha256.convert(utf8.encode(jsonEncode(state))).toString() !=
            json['sha256']) {
      throw const FormatException('备份格式无效或文件已损坏');
    }
    return ConfigBackup(time, state);
  }
}

// Version 1 fixes all cipher/KDF parameters; files cannot request expensive
// arbitrary parameters. A new salt and GCM nonce are used on every export.
const backupFileLimit = 32 * 1024 * 1024;
final _kdf = Pbkdf2.hmacSha256(iterations: 600000, bits: 256);

Future<Uint8List> encryptBackup(ConfigBackup backup, String password) =>
    Isolate.run(() async {
      if (password.isEmpty) throw const FormatException('请输入备份密码');
      final random = Random.secure();
      final salt = List<int>.generate(16, (_) => random.nextInt(256));
      final key = await _kdf.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final box = await AesGcm.with256bits().encrypt(
        utf8.encode(jsonEncode(backup.toJson())),
        secretKey: key,
      );
      final bytes = utf8.encode(
        jsonEncode({
          'format': 'fcxray.encrypted-backup',
          'version': 1,
          'salt': base64Encode(salt),
          'box': base64Encode(box.concatenation()),
        }),
      );
      if (bytes.length > backupFileLimit) {
        throw const FormatException('备份文件超过 32 MiB');
      }
      return bytes;
    });

Future<ConfigBackup> decryptBackup(Uint8List bytes, String password) =>
    Isolate.run(() async {
      if (bytes.length > backupFileLimit) {
        throw const FormatException('备份文件超过 32 MiB');
      }
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map ||
          json['format'] != 'fcxray.encrypted-backup' ||
          json['version'] != 1 ||
          json['salt'] is! String ||
          json['box'] is! String) {
        throw const FormatException('备份文件无效');
      }
      final salt = base64Decode(json['salt'] as String),
          data = base64Decode(json['box'] as String);
      if (salt.length != 16 || data.length <= 28) {
        throw const FormatException('备份文件无效');
      }
      final key = await _kdf.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final plain = await AesGcm.with256bits().decrypt(
        SecretBox.fromConcatenation(data, nonceLength: 12, macLength: 16),
        secretKey: key,
      );
      return ConfigBackup.fromJson(
        jsonDecode(utf8.decode(plain)) as Map<String, dynamic>,
      );
    });
