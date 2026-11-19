// Windows-only calls, run off the UI isolate. The old secure-storage key is
// still readable until the first atomic save commits the new state file.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

Uint8List _dpapi(Uint8List bytes, {required bool encrypt}) => using((arena) {
  final data = arena<Uint8>(bytes.length)
    ..asTypedList(bytes.length).setAll(0, bytes);
  final input = arena<CRYPT_INTEGER_BLOB>();
  input.ref.cbData = bytes.length;
  input.ref.pbData = data;
  final output = arena<CRYPT_INTEGER_BLOB>();
  try {
    const forbidUi = 1; // CRYPTPROTECT_UI_FORBIDDEN
    final result = encrypt
        ? CryptProtectData(input, null, null, null, forbidUi, output)
        : CryptUnprotectData(input, null, null, null, forbidUi, output);
    if (!result.value) {
      throw FileSystemException('Windows 安全存储操作失败（${result.error}）');
    }
    final buffer = output.ref.pbData.asTypedList(output.ref.cbData);
    try {
      return Uint8List.fromList(buffer);
    } finally {
      if (!encrypt) buffer.fillRange(0, buffer.length, 0);
      LocalFree(HLOCAL(output.ref.pbData.cast()));
    }
  } finally {
    if (encrypt) data.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
  }
});

class WindowsStateFile {
  WindowsStateFile(this.file);
  final File file;

  static Future<WindowsStateFile> open({
    bool backup = false,
  }) async => WindowsStateFile(
    File(
      '${(await getApplicationSupportDirectory()).path}/fcxray-${backup ? 'backup' : 'state'}.dpapi',
    ),
  );

  // Version 4 of flutter_secure_storage_windows stored a DPAPI-protected JSON
  // map here. Its normal read path deletes unreadable blobs; recovery must
  // leave the original in place until the user chooses what to save.
  static Future<String?> readLegacy(String key) async {
    final dir = await getApplicationSupportDirectory();
    final raw = await WindowsStateFile(
      File('${dir.path}/flutter_secure_storage.dat'),
    ).read();
    return raw == null ? null : (jsonDecode(raw) as Map)[key] as String?;
  }

  Future<String?> read() async {
    return Isolate.run(() {
      late final Uint8List bytes;
      try {
        bytes = file.readAsBytesSync();
      } on FileSystemException catch (e) {
        if (e.osError?.errorCode == 2 || e.osError?.errorCode == 3) return null;
        rethrow;
      }
      return utf8.decode(_dpapi(bytes, encrypt: false));
    });
  }

  Future<void> write(String value) async {
    await Isolate.run(() {
      file.parent.createSync(recursive: true);
      // An OS-owned lock is released even if the process is killed.
      final lock = File('${file.path}.lock').openSync(mode: FileMode.append);
      try {
        lock.lockSync(FileLock.blockingExclusive);
        final stage = File('${file.path}.new');
        try {
          stage.writeAsBytesSync(
            _dpapi(utf8.encode(value), encrypt: true),
            flush: true,
          );
          using((arena) {
            final result = MoveFileEx(
              arena.pcwstr(stage.path),
              arena.pcwstr(file.path),
              MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
            );
            if (!result.value) {
              throw FileSystemException('无法提交 Windows 安全存储（${result.error}）');
            }
          });
        } finally {
          if (stage.existsSync()) stage.deleteSync();
        }
      } finally {
        lock.closeSync();
      }
    });
  }
}
