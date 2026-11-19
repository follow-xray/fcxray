import 'dart:convert';
import 'dart:io';
import 'windows_state_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class ProfileStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
}

class SecureProfileStore implements ProfileStore {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static const _key = 'fcxray.state.v1';
  bool _legacyCleanupDone = false;

  @override
  Future<Map<String, dynamic>?> read() async {
    String? raw;
    if (Platform.isWindows) raw = await (await WindowsStateFile.open()).read();
    raw ??= await _storage.read(key: _key);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<void> write(Map<String, dynamic> value) async {
    final raw = jsonEncode(value);
    if (!Platform.isWindows) {
      await _storage.write(key: _key, value: raw);
      if (Platform.isAndroid) {
        await const MethodChannel(
          'com.fcxray.client/preferences',
        ).invokeMethod<void>('flush');
      }
      return;
    }
    await (await WindowsStateFile.open()).write(raw);
    if (!_legacyCleanupDone) {
      try {
        await _storage.delete(key: _key);
        _legacyCleanupDone = true;
      } on Exception {
        // The new file is already committed. Retry legacy cleanup on next save.
      }
    }
  }
}
