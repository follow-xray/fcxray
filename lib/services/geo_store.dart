import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import '../models/profile.dart';
import '../models/resources.dart';
import 'core_backend.dart';

class GeoStore {
  GeoStore({required this.backend, this.directory});
  final CoreBackend backend;
  final Directory? directory;
  Future<Directory> root() async {
    final base =
        directory ??
        Directory('${(await getApplicationSupportDirectory()).path}/geodata');
    await base.create(recursive: true);
    return base;
  }

  static String? fileDigest(String kind, String name) {
    if (kind != 'geoip' && kind != 'geosite') return null;
    return RegExp(
      '^$kind-([0-9a-f]{64})(?:-[1-9][0-9]*)?\\.dat\$',
    ).firstMatch(name)?.group(1);
  }

  static Future<bool> _matches(File file, int size, String hash) async {
    if (size <= 0 || size > 64 * 1024 * 1024 || await file.length() != size) {
      return false;
    }
    return Isolate.run(
      () async =>
          (await sha256.bind(file.openRead(0, size + 1)).single).toString() ==
          hash,
    );
  }

  Future<GeoAsset> install(GeoAsset previous, Stream<List<int>> bytes) async {
    final dir = await root();
    final stage = File('${dir.path}/.stage-${Profile.newId()}.dat');
    try {
      final sink = stage.openWrite();
      try {
        var size = 0;
        await for (final chunk in bytes) {
          size += chunk.length;
          if (size > 64 * 1024 * 1024) {
            throw const FormatException('规则库不能超过 64 MiB');
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      final info = await backend.call(
        'geo',
        jsonEncode({'kind': previous.kind, 'path': stage.absolute.path}),
      );
      final hash = info['sha256'] as String;
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
        throw const FormatException('内核返回的摘要无效');
      }
      if (previous.expectedHash.isNotEmpty &&
          previous.expectedHash.toLowerCase() != hash) {
        throw const FormatException('SHA-256 与预期不符，已保留旧规则库');
      }
      final size = info['size'] as int;
      final base = '${previous.kind}-$hash';
      var name = '$base.dat';
      for (var suffix = 1; ; suffix++) {
        final target = File('${dir.path}/$name');
        if (!await target.exists()) {
          await stage.rename(target.path);
          break;
        }
        if (await _matches(target, size, hash)) break;
        // A live session may still reference the damaged file by name.
        name = '$base-$suffix.dat';
      }
      // Immutable filenames prevent stale core caches and keep prior versions usable.
      final now = DateTime.now().toIso8601String();
      return GeoAsset.fromJson({
        ...previous.toJson(),
        'fileName': name,
        'hash': hash,
        'size': info['size'],
        'entries': info['entries'],
        'tags': info['tags'],
        'updatedAt': now,
        'attemptedAt': now,
        'error': null,
      });
    } finally {
      if (await stage.exists()) await stage.delete();
    }
  }

  Future<void> ensureAvailable(Iterable<GeoAsset> assets) async {
    final dir = await root();
    for (final asset in assets.where((a) => a.installed)) {
      final name = asset.fileName!;
      final hash = fileDigest(asset.kind, name);
      if (hash == null || (asset.hash.isNotEmpty && hash != asset.hash)) {
        throw const FormatException('规则库文件名或摘要无效，请重新导入');
      }
      final file = File('${dir.path}/$name');
      if (!await file.exists()) {
        throw FormatException('${asset.kind} 文件已丢失，请重新导入或更新');
      }
      if (!await _matches(file, asset.size, hash)) {
        throw FormatException('${asset.kind} 文件已损坏，请重新导入或更新');
      }
    }
  }
}
