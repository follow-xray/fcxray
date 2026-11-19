import 'dart:io';
import 'dart:typed_data';

enum TargetKind {
  domain('域名及子域名'),
  exact('精确域名'),
  ip('IP / 网段');

  const TargetKind(this.label);
  final String label;
}

enum RouteAction {
  direct('直连'),
  proxy('代理'),
  block('拒绝');

  const RouteAction(this.label);
  final String label;
}

class RouteOverride {
  const RouteOverride._(this.kind, this.target, this.action, this.enabled);
  final TargetKind kind;
  final String target;
  final RouteAction action;
  final bool enabled;
  String get key => '${kind.name}:$target';

  factory RouteOverride.parse(
    TargetKind kind,
    String raw,
    RouteAction action, {
    bool enabled = true,
  }) {
    var value = raw.trim().toLowerCase();
    if (kind == TargetKind.ip) {
      final parts = value.split('/');
      final ip = InternetAddress.tryParse(parts.first);
      if (ip == null || parts.length > 2 || value.contains('%')) {
        throw const FormatException('请输入 IPv4、IPv6 或 CIDR 网段，如 10.0.0.0/8');
      }
      final bytes = Uint8List.fromList(ip.rawAddress);
      final width = bytes.length * 8;
      final prefix = parts.length == 1 ? width : int.tryParse(parts.last);
      if (prefix == null || prefix < 0 || prefix > width) {
        throw FormatException('网段前缀长度应为 0–$width');
      }
      for (var i = 0; i < bytes.length; i++) {
        final keep = (prefix - i * 8).clamp(0, 8);
        bytes[i] &= (0xff << (8 - keep)) & 0xff;
      }
      value = InternetAddress.fromRawAddress(bytes).address;
      if (prefix < width) value = '$value/$prefix';
    } else {
      if (value.endsWith('.')) value = value.substring(0, value.length - 1);
      final label = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
      if (value.length > 253 ||
          !value.split('.').every(label.hasMatch) ||
          RegExp(r'^[.0-9]+$').hasMatch(value)) {
        throw const FormatException('请输入域名，如 example.com；国际化域名请使用 Punycode');
      }
    }
    return RouteOverride._(kind, value, action, enabled);
  }
  RouteOverride toggle() => RouteOverride._(kind, target, action, !enabled);
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'target': target,
    'action': action.name,
    'enabled': enabled,
  };
  factory RouteOverride.fromJson(Map<String, dynamic> data) =>
      RouteOverride.parse(
        TargetKind.values.byName(data['kind']),
        data['target'],
        RouteAction.values.byName(data['action']),
        enabled: data['enabled'] ?? true,
      );
  Map<String, dynamic> toXray() => {
    'type': 'field',
    if (kind == TargetKind.ip)
      'ip': [target]
    else
      'domain': ['${kind == TargetKind.exact ? 'full' : 'domain'}:$target'],
    'outboundTag': action.name,
  };
}
