import 'dart:convert';
import 'dart:math';
import '../services/protocol_catalog.dart';

class Profile {
  Profile({
    required this.id,
    required this.name,
    required this.outbound,
    this.subscriptionId,
  });

  final String? subscriptionId;
  final String id;
  final String name;
  final Map<String, dynamic> outbound;
  String get protocol =>
      ProtocolCatalog.canonical(outbound['protocol'] as String);
  String get host => ProtocolCatalog.endpoint(outbound).host;
  int get port => ProtocolCatalog.endpoint(outbound).port;
  String get endpointLabel =>
      port > 0 ? '${host.contains(':') ? '[$host]' : host}:$port' : host;
  bool get isUtility => ProtocolCatalog.utility.contains(protocol);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'outbound': outbound,
    'subscriptionId': subscriptionId,
  };
  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    subscriptionId: json['subscriptionId'] as String?,
    name: json['name'] as String,
    outbound: Map<String, dynamic>.from(json['outbound'] as Map),
  );
  static String newId() =>
      base64Url.encode(List.generate(18, (_) => Random.secure().nextInt(256)));
  Profile copy({String? id, String? subscriptionId}) => Profile(
    id: id ?? this.id,
    name: name,
    outbound: outbound,
    subscriptionId: subscriptionId ?? this.subscriptionId,
  );
  factory Profile.create(String name, Map<String, dynamic> outbound) {
    final id = newId();
    return Profile(id: id, name: name, outbound: {...outbound, 'tag': 'proxy'});
  }
}
