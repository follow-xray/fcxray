import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import '../models/route_override.dart';

class RuleExchange {
  static const _format = 'fcxray.route-overrides';
  static const _type = XTypeGroup(
    label: 'JSON',
    extensions: ['json'],
    mimeTypes: ['application/json', 'text/plain'],
    uniformTypeIdentifiers: ['public.json'],
  );
  static const _limit = 1024 * 1024;
  static String encode(List<RouteOverride> rules) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': _format,
        'version': 1,
        'rules': rules.map((r) => r.toJson()).toList(),
      });

  static List<RouteOverride> decode(String source) {
    final data = jsonDecode(source);
    final Object? entries;
    if (data is Map) {
      if (data['format'] != _format || data['version'] != 1) {
        throw const FormatException('请使用 fcxray 自定义规则 JSON（版本 1）');
      }
      entries = data['rules'];
    } else {
      entries = data;
    }
    if (entries is! List) throw const FormatException('缺少规则数组');
    final rules = <RouteOverride>[];
    final keys = <String>{};
    for (final (i, entry) in entries.indexed) {
      try {
        if (entry is! Map<String, dynamic> ||
            entry['kind'] is! String ||
            entry['target'] is! String ||
            entry['action'] is! String ||
            (entry.containsKey('enabled') && entry['enabled'] is! bool)) {
          throw const FormatException('字段或类型无效');
        }
        final rule = RouteOverride.fromJson(entry);
        if (!keys.add(rule.key)) throw const FormatException('匹配目标重复');
        rules.add(rule);
      } on Object catch (e) {
        throw FormatException(
          '第 ${i + 1} 条规则：${e is FormatException ? e.message : "未知的匹配方式或流量去向"}',
        );
      }
    }
    return rules;
  }

  static Future<List<RouteOverride>?> pick() async {
    final file = await openFile(acceptedTypeGroups: [_type]);
    if (file == null) return null;
    if (await file.length() > _limit) {
      throw const FormatException('规则文件不能超过 1 MiB');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > _limit) {
        throw const FormatException('规则文件不能超过 1 MiB');
      }
      bytes.add(chunk);
    }
    return decode(utf8.decode(bytes.takeBytes()));
  }

  static Future<bool> save(List<RouteOverride> rules) async {
    final bytes = utf8.encode(encode(rules));
    if (bytes.length > _limit) throw const FormatException('规则文件不能超过 1 MiB');
    if (Platform.isAndroid) {
      return await const MethodChannel(
            'com.fcxray.client/documents',
          ).invokeMethod<bool>('saveRules', bytes) ??
          false;
    }
    final location = await getSaveLocation(
      suggestedName: 'fcxray-rules.json',
      acceptedTypeGroups: [_type],
    );
    if (location == null) return false;
    await XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: 'fcxray-rules.json',
    ).saveTo(location.path);
    return true;
  }
}
