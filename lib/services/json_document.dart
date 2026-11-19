import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

enum JsonDocument {
  rules('fcxray-rules.json', 'saveRules', 1024 * 1024),
  backup('fcxray-backup.json', 'saveBackup', 32 * 1024 * 1024);

  const JsonDocument(this.name, this.androidMethod, this.limit);
  final String name, androidMethod;
  final int limit;
  static const _type = XTypeGroup(
    label: 'JSON',
    extensions: ['json'],
    mimeTypes: ['application/json', 'text/plain'],
    uniformTypeIdentifiers: ['public.json'],
  );
  Future<Uint8List?> pick() async {
    final file = await openFile(acceptedTypeGroups: [_type]);
    if (file == null) return null;
    final tooLarge = FormatException('文件不能超过 ${limit ~/ (1024 * 1024)} MiB');
    if (await file.length() > limit) throw tooLarge;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > limit) throw tooLarge;
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<bool> save(Uint8List bytes) async {
    if (bytes.length > limit) {
      throw FormatException('文件不能超过 ${limit ~/ (1024 * 1024)} MiB');
    }
    if (Platform.isAndroid) {
      return await const MethodChannel(
            'com.fcxray.client/documents',
          ).invokeMethod<bool>(androidMethod, bytes) ??
          false;
    }
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [_type],
    );
    if (location == null) return false;
    await XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: name,
    ).saveTo(location.path);
    return true;
  }
}
