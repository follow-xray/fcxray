import 'dart:convert';
import 'dart:io';
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
      final name = '${previous.kind}-$hash.dat';
      final target = File('${dir.path}/$name');
      if (!await target.exists()) {
        await stage.rename(target.path);
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
      if (!RegExp(
        '^${asset.kind}-[0-9a-f]{64}\\.dat\$',
      ).hasMatch(asset.fileName!)) {
        throw const FormatException('规则库文件名无效，请重新导入');
      }
      if (!await File('${dir.path}/${asset.fileName}').exists()) {
        throw FormatException('${asset.kind} 文件已丢失，请重新导入或更新');
      }
    }
  }
}
