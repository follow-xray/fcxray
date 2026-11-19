import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class ProfileStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
}

class SecureProfileStore implements ProfileStore {
  final _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static const _key = 'fcxray.state.v1';
  @override
  Future<Map<String, dynamic>?> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<void> write(Map<String, dynamic> value) =>
      _storage.write(key: _key, value: jsonEncode(value));
}
