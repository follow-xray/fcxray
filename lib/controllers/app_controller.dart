import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import '../models/profile.dart';
import '../models/resources.dart';
import '../models/route_override.dart';
import '../services/config_builder.dart';
import '../services/core_backend.dart';
import '../services/geo_store.dart';
import '../services/profile_importer.dart';
import '../services/profile_store.dart';
import '../services/node_latency.dart';
import '../services/resource_fetcher.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, failed }

class AppController extends ChangeNotifier {
  AppController({
    required this.backend,
    required this.store,
    required this.platform,
    this.fetcher = const ResourceFetcher(),
    GeoStore? geoStore,
    NodeLatency? latency,
  }) {
    this.latency = latency ?? NodeLatency();
    this.latency.addListener(_notify);
    geo = geoStore ?? GeoStore(backend: backend);
  }
  final CoreBackend backend;
  final ProfileStore store;
  final String platform;
  final ResourceFetcher fetcher;
  late final GeoStore geo;
  late final NodeLatency latency;
  List<Profile> profiles = [];
  List<Subscription> subscriptions = [];
  Map<String, GeoAsset> geoAssets = {
    for (final kind in ['geoip', 'geosite']) kind: GeoAsset.defaults(kind),
  };
  GeoRouting geoRouting = const GeoRouting();
  String? selectedId;
  Profile? _activeProfile;
  String? _activeConfig, _sessionId;
  Uri? _activeHttpProxy;
  Profile? get activeProfile => connected ? _activeProfile : null;
  Profile? get displayProfile => connected ? _activeProfile : selected;
  bool get resourcesEditable => loaded && !busy && !saving;
  bool get canToggle =>
      loaded &&
      !busy &&
      (connected ||
          (!saving && (routing == RoutingMode.direct || selected != null)));
  bool get pendingChanges {
    if (!connected || _activeConfig == null) return false;
    try {
      return jsonEncode(buildConfig()) != _activeConfig;
    } on Object {
      return true;
    }
  }

  ConnectionMode mode = ConnectionMode.vpn;
  RoutingMode routing = RoutingMode.rules;
  bool bypassLan = true, useGeo = false;
  bool get geoEnabled => routing == RoutingMode.rules && useGeo;
  List<RouteOverride> overrides = [];
  String? _activeAssets;
  VpnStatus status = VpnStatus.disconnected;
  bool loaded = false,
      saving = false,
      _polling = false,
      _disposed = false,
      _maintaining = false;
  String? error;
  String coreVersion = '待检测';
  int upload = 0, download = 0, uptime = 0;
  double uploadRate = 0, downloadRate = 0;
  DateTime? _lastPoll;
  final List<String> logs = [];
  Timer? _timer, _maintenance;
  bool _visible = true, _overview = true;
  int _sessionRevision = 0;

  void setPollingView({required bool visible, required bool overview}) {
    if (_visible == visible && _overview == overview) return;
    final resume = visible && (!_visible || (overview && !_overview));
    _visible = visible;
    _overview = overview;
    if (_timer == null || _disposed || _exiting) return;
    _scheduleStatusPoll();
    if (resume) unawaited(refresh());
  }

  void _scheduleStatusPoll() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(
        seconds: !_visible
            ? 30
            : _overview
            ? 1
            : 5,
      ),
      (_) => unawaited(refresh()),
    );
  }

  bool _switchingNode = false;
  bool _exiting = false;
  bool get busy =>
      _switchingNode ||
      _exiting ||
      status == VpnStatus.connecting ||
      status == VpnStatus.disconnecting;
  bool get connected => status == VpnStatus.connected;
  bool get editable => loaded && !busy && !connected && !saving;
  Profile? get selected =>
      profiles.where((p) => p.id == selectedId).firstOrNull;
  String sourceName(Profile p) =>
      subscriptions.where((s) => s.id == p.subscriptionId).firstOrNull?.name ??
      '手动节点';
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _log(String message) {
    logs.insert(
      0,
      '${DateTime.now().toIso8601String().substring(11, 19)}  $message',
    );
    if (logs.length > 100) logs.removeLast();
  }

  final _themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
  ValueListenable<ThemeMode> get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode next) async {
    if (next == _themeMode.value) return;
    await _change(() async {
      _themeMode.value = next;
    }, allowConnected: true);
  }

  SubscriptionAgent subscriptionAgent = SubscriptionAgent.xray;
  String customSubscriptionAgent = '';
  String get subscriptionHeader =>
      subscriptionAgent.header(platform, customSubscriptionAgent);

  Future<void> setSubscriptionAgent(
    SubscriptionAgent mode,
    String custom,
  ) async {
    if (mode == SubscriptionAgent.custom &&
        !SubscriptionAgent.validCustom(custom)) {
      throw const FormatException('请输入非空的单行 ASCII User-Agent');
    }
    await _change(() async {
      subscriptionAgent = mode;
      if (mode == SubscriptionAgent.custom) {
        customSubscriptionAgent = custom.trim();
      }
    }, allowConnected: true);
  }

  void _restore(Map<String, dynamic> value, {List<Profile>? retainedProfiles}) {
    final custom = value['customSubscriptionAgent'];
    customSubscriptionAgent =
        custom is String && SubscriptionAgent.validCustom(custom)
        ? custom.trim()
        : '';
    subscriptionAgent =
        SubscriptionAgent.values
            .where(
              (agent) =>
                  agent.name == value['subscriptionAgent'] &&
                  (agent != SubscriptionAgent.custom ||
                      customSubscriptionAgent.isNotEmpty),
            )
            .firstOrNull ??
        SubscriptionAgent.xray;
    _themeMode.value =
        ThemeMode.values
            .where((mode) => mode.name == value['themeMode'])
            .firstOrNull ??
        ThemeMode.system;
    profiles =
        retainedProfiles ??
        (value['profiles'] as List? ?? [])
            .map((p) => Profile.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList();
    subscriptions = (value['subscriptions'] as List? ?? [])
        .map((s) => Subscription.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList();
    final assets = value['geoAssets'] as Map? ?? {};
    geoAssets = {
      for (final kind in ['geoip', 'geosite'])
        kind: assets[kind] == null
            ? GeoAsset.defaults(kind)
            : GeoAsset.fromJson(Map<String, dynamic>.from(assets[kind] as Map)),
    };
    geoRouting = GeoRouting.fromJson(
      Map<String, dynamic>.from(value['geoRouting'] as Map? ?? {}),
    );
    selectedId = value['selectedId'] as String?;
    if (selected == null) selectedId = profiles.firstOrNull?.id;
    mode = platform == 'android'
        ? ConnectionMode.vpn
        : ConnectionMode.values.byName(value['mode'] as String? ?? 'vpn');
    final saved = value['routing'] as String? ?? 'bypassLan';
    routing = switch (saved) {
      'bypassLan' || 'geoRules' => RoutingMode.rules,
      _ => RoutingMode.values.byName(saved),
    };
    bypassLan = value['bypassLan'] as bool? ?? true;
    useGeo = value['useGeo'] as bool? ?? (saved == 'geoRules');
    overrides = (value['routeOverrides'] as List? ?? [])
        .map((v) => RouteOverride.fromJson(Map<String, dynamic>.from(v)))
        .toList();
  }

  Map<String, dynamic> _state() => {
    'schemaVersion': 3,
    'themeMode': _themeMode.value.name,
    'subscriptionAgent': subscriptionAgent.name,
    'customSubscriptionAgent': customSubscriptionAgent,
    'bypassLan': bypassLan,
    'useGeo': useGeo,
    'routeOverrides': overrides.map((r) => r.toJson()).toList(),
    'profiles': profiles.map((p) => p.toJson()).toList(),
    'subscriptions': subscriptions.map((s) => s.toJson()).toList(),
    'geoAssets': geoAssets.map((key, asset) => MapEntry(key, asset.toJson())),
    'geoRouting': geoRouting.toJson(),
    'selectedId': selectedId,
    'mode': mode.name,
    'routing': routing.name,
  };

  bool initializing = false;
  Future<void> initialize({bool poll = true}) async {
    if (initializing || loaded || _disposed) return;
    initializing = true;
    final previous = _state();
    error = null;
    _notify();
    try {
      final value = await store.read();
      if (_disposed) return;
      if (value != null) _restore(value);
      loaded = true;
      _log('配置已加载');
    } on Object catch (e) {
      if (_disposed) return;
      _restore(previous);
      error = e is FormatException || e is TypeError || e is ArgumentError
          ? '已保存的配置格式无效，原数据已保留。'
          : '无法读取安全存储，请检查系统钥匙串或存储权限后重试。';
      _log(error!);
    } finally {
      initializing = false;
    }
    if (poll && loaded) {
      await refresh();
      if (_disposed || _exiting) return;
      _scheduleStatusPoll();
      _maintenance = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(updateDue()),
      );
      unawaited(updateDue());
    }
    _notify();
  }

  Future<T> _change<T>(
    Future<T> Function() action, {
    bool allowConnected = false,
  }) async {
    if (!(allowConnected ? resourcesEditable : editable)) {
      throw StateError('请先断开连接并等待当前操作完成');
    }
    final before = _state();
    final previousProfiles = profiles;
    saving = true;
    error = null;
    _notify();
    try {
      final result = await action();
      await store.write(_state());
      return result;
    } on Object {
      _restore(before, retainedProfiles: previousProfiles);
      rethrow;
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<void> _quiet(Future<void> Function() action) async {
    try {
      await _change(action);
    } on Object catch (e) {
      error = e is FormatException ? e.message : '配置保存失败，请检查安全存储或当前连接状态。';
      _notify();
    }
  }

  static String fingerprint(Profile p) {
    Object? canonical(Object? value) {
      if (value is Map) {
        final keys = value.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: canonical(value[key])};
      }
      if (value is List) return value.map(canonical).toList();
      return value;
    }

    return sha256
        .convert(utf8.encode(jsonEncode(canonical(p.outbound))))
        .toString();
  }

  Future<int> importText(String input) => _change(() async {
    final parsed = ProfileImporter.parse(input);
    final known = profiles
        .where((p) => p.subscriptionId == null)
        .map(fingerprint)
        .toSet();
    final additions = parsed.where((p) => known.add(fingerprint(p))).toList();
    profiles = [...profiles, ...additions];
    selectedId ??= profiles.firstOrNull?.id;
    _log('已导入 ${additions.length} 个手动节点');
    return additions.length;
  });

  Future<void> saveManual(Profile profile, {String? replacingId}) =>
      _change(() async {
        await backend.call(
          'validate',
          jsonEncode(
            ConfigBuilder.build(
              profile,
              platform: platform,
              mode: ConnectionMode.proxy,
              routing: RoutingMode.global,
            ),
          ),
        );
        final saved = Profile(
          id: replacingId ?? profile.id,
          name: profile.name,
          outbound: profile.outbound,
        );
        if (replacingId == null) {
          profiles = [...profiles, saved];
        } else {
          profiles = profiles
              .map((p) => p.id == replacingId ? saved : p)
              .toList();
        }
        selectedId ??= saved.id;
        _log(replacingId == null ? '已创建手动节点' : '已修改手动节点');
      });
  Future<void> select(String id) async {
    if (!editable || !profiles.any((p) => p.id == id)) return;
    await _quiet(() async {
      selectedId = id;
    });
  }

  Future<void> remove(String id) async {
    if (!editable) return;
    await _quiet(() async {
      profiles = profiles.where((p) => p.id != id).toList();
      if (selectedId == id) selectedId = profiles.firstOrNull?.id;
    });
  }

  Future<void> settings(ConnectionMode newMode, RoutingMode newRouting) async {
    if (!editable) return;
    await _quiet(() async {
      mode = platform == 'android' ? ConnectionMode.vpn : newMode;
      routing = newRouting;
      if (selected != null && geoEnabled) {
        await _validateSelection();
      }
    });
  }

  Future<List<String>> addSubscriptions(String name, String lines, int hours) =>
      _change(() async {
        final urls = const LineSplitter()
            .convert(lines)
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
        if (urls.isEmpty || urls.length > 30) {
          throw const FormatException('每次请输入 1–30 个订阅地址，每行一个');
        }
        for (final url in urls) {
          fetcher.validateUrl(url);
        }
        final known = subscriptions.map((s) => s.url).toSet();
        final additions = <Subscription>[];
        for (final url in urls.where((u) => known.add(u))) {
          final label = name.trim().isEmpty
              ? Uri.parse(url).host
              : (urls.length == 1
                    ? name.trim()
                    : '${name.trim()} ${additions.length + 1}');
          additions.add(Subscription.create(label, url, hours));
        }
        subscriptions = [...subscriptions, ...additions];
        _log('已添加 ${additions.length} 个订阅');
        return additions.map((s) => s.id).toList();
      }, allowConnected: true);
  Future<void> editSubscription(Subscription value) => _change(() async {
    fetcher.validateUrl(value.url);
    if (subscriptions.any((s) => s.id != value.id && s.url == value.url)) {
      throw const FormatException('此订阅地址已存在');
    }
    final current = subscriptions.firstWhere((s) => s.id == value.id);
    final sameSource = current.url == value.url;
    final updated = Subscription(
      id: current.id,
      name: value.name,
      url: value.url,
      autoHours: value.autoHours,
      updatedAt: current.updatedAt,
      attemptedAt: sameSource ? current.attemptedAt : null,
      error: sameSource ? current.error : null,
      usage: sameSource ? current.usage : null,
    );
    subscriptions = subscriptions
        .map((s) => s.id == value.id ? updated : s)
        .toList();
  }, allowConnected: true);
  Future<void> removeSubscription(String id) => _change(() async {
    subscriptions = subscriptions.where((s) => s.id != id).toList();
    profiles = profiles.where((p) => p.subscriptionId != id).toList();
    if (selected == null) selectedId = profiles.firstOrNull?.id;
  }, allowConnected: true);

  Future<bool> updateSubscription(String id) => _change(() async {
    final subscription = subscriptions.firstWhere((s) => s.id == id);
    try {
      SubscriptionUsage? usage;
      final parsed = ProfileImporter.parse(
        await fetcher.subscription(
          subscription.url,
          userAgent: subscriptionHeader,
          onUsage: (value) => usage = value,
          proxy: connected ? _activeHttpProxy : null,
          onRoute: _downloadRoute,
        ),
      );
      if (parsed.length > 2000) {
        throw const FormatException('单个订阅最多支持 2000 个节点');
      }
      final old = {
        for (final p in profiles.where((p) => p.subscriptionId == id))
          fingerprint(p): p,
      };
      final seen = <String>{};
      final updated = <Profile>[];
      for (final p in parsed) {
        final key = fingerprint(p);
        if (seen.add(key)) {
          final previous = old[key];
          updated.add(
            previous != null && previous.name == p.name
                ? previous
                : p.copy(id: previous?.id, subscriptionId: id),
          );
        }
      }
      final selectedWasHere = selected?.subscriptionId == id;
      final first = profiles.indexWhere((p) => p.subscriptionId == id);
      final insertAt = first < 0 ? profiles.length : first;
      profiles = [
        ...profiles.take(insertAt),
        ...updated,
        ...profiles.skip(insertAt).where((p) => p.subscriptionId != id),
      ];
      if (selected == null) {
        selectedId =
            (selectedWasHere ? updated.firstOrNull : profiles.firstOrNull)?.id;
      }
      subscriptions = subscriptions
          .map(
            (s) => s.id == id ? s.result(now: DateTime.now(), usage: usage) : s,
          )
          .toList();
      _log('订阅更新成功：${updated.length} 个节点');
      return true;
    } on Object {
      const message = '下载或解析失败，保留上次节点；请检查地址、网络及订阅格式。';
      subscriptions = subscriptions
          .map(
            (s) => s.id == id
                ? s.result(now: DateTime.now(), failure: message)
                : s,
          )
          .toList();
      _log('订阅更新失败，已保留原节点');
      return false;
    }
  }, allowConnected: true);
  Future<void> updateSubscriptions([List<String>? ids]) async {
    for (final id in ids ?? subscriptions.map((s) => s.id).toList()) {
      if (!resourcesEditable || _disposed) break;
      await updateSubscription(id);
    }
  }

  Future<void> configureGeo(GeoAsset value) => _change(() async {
    fetcher.validateUrl(value.url);
    if (value.expectedHash.isNotEmpty &&
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value.expectedHash)) {
      throw const FormatException('SHA-256 应为 64 位十六进制字符');
    }
    final current = geoAssets[value.kind]!;
    final updated = GeoAsset.fromJson({
      ...current.toJson(),
      'url': value.url,
      'expectedHash': value.expectedHash,
      'autoHours': value.autoHours,
      if (current.url != value.url) 'attemptedAt': null,
      if (current.url != value.url) 'error': null,
    });
    geoAssets = {...geoAssets, value.kind: updated};
  }, allowConnected: true);
  Future<void> importGeo(String kind, Stream<List<int>> bytes) =>
      _change(() async {
        final installed = await geo.install(geoAssets[kind]!, bytes);
        geoAssets = {...geoAssets, kind: installed};
        if (geoEnabled && selected != null) {
          await _validateSelection();
        }
        _log('$kind 规则库导入成功');
      }, allowConnected: true);
  Future<bool> updateGeo(String kind) => _change(() async {
    final previous = geoAssets[kind]!;
    try {
      final installed = await fetcher.fetch(
        previous.url,
        limit: 64 * 1024 * 1024,
        proxy: connected ? _activeHttpProxy : null,
        onRoute: _downloadRoute,
        consume: (bytes) => geo.install(previous, bytes),
      );
      geoAssets = {...geoAssets, kind: installed};
      if (geoEnabled && selected != null) {
        await _validateSelection();
      }
      _log('$kind 规则库更新成功');
      return true;
    } on Object catch (e) {
      final message = e is FormatException ? e.message : '规则库下载或校验失败，已保留上一版本';
      geoAssets = {...geoAssets, kind: previous.failure(message)};
      _log('$kind 更新失败，已保留上一版本');
      return false;
    }
  }, allowConnected: true);
  Future<void> setGeoRouting(GeoRouting value) => _change(() async {
    geoRouting = value;
    if (selected != null && geoEnabled) {
      await _validateSelection();
    }
  }, allowConnected: true);
  Map<String, dynamic> buildConfig() {
    return ConfigBuilder.build(
      selected,
      platform: platform,
      mode: mode,
      routing: routing,
      geoAssets: geoAssets,
      geoRouting: geoRouting,
      useGeo: useGeo,
      bypassLan: bypassLan,
      overrides: overrides,
    );
  }

  Future<String?> _assetDirectory() async {
    if (!geoEnabled) return null;
    await geo.ensureAvailable(geoAssets.values);
    return (await geo.root()).absolute.path;
  }

  Future<void> _validateSelection() async {
    final config = jsonEncode(buildConfig());
    final directory = await _assetDirectory();
    // Do not load a prospective config or switch process-global assets while the
    // core is forwarding traffic. The next start performs the full native check.
    if (!connected) await backend.call('validate', config, directory);
  }

  void _downloadRoute(DownloadRoute route) {
    _log(route == DownloadRoute.proxy ? '资源下载：优先使用当前本地代理' : '资源下载：使用系统网络');
    _notify();
  }

  void _rememberSession(Map<String, dynamic> data, {Profile? hint}) {
    final config = data['config'] as String?;
    if (data['running'] != true || config == null || config.isEmpty) return;
    final decoded = jsonDecode(config) as Map<String, dynamic>;
    final outbounds = (decoded['outbounds'] as List? ?? []).cast<Map>();
    final outbound =
        outbounds.where((o) => o['tag'] == 'proxy').firstOrNull ??
        outbounds.firstOrNull;
    if (outbound != null) {
      final raw = Profile.create(
        outbound['tag'] == 'direct' ? '系统直连' : '当前连接',
        Map<String, dynamic>.from(outbound),
      );
      final match = outbound['tag'] == 'direct'
          ? null
          : hint ??
                profiles
                    .where((p) => fingerprint(p) == fingerprint(raw))
                    .firstOrNull;
      _activeProfile = Profile(
        id: match?.id ?? raw.id,
        name: match?.name ?? '当前连接',
        outbound: raw.outbound,
      );
    }
    _activeConfig = config;
    _activeAssets = data['assetDirectory'] as String?;
    _sessionId = data['sessionId'] as String?;
    _activeHttpProxy = null;
    for (final inbound in (decoded['inbounds'] as List? ?? [])) {
      if (inbound['protocol'] == 'http' &&
          ['127.0.0.1', '::1'].contains(inbound['listen'])) {
        final port = inbound['port'];
        if (port is int && port > 0 && port <= 65535) {
          _activeHttpProxy = Uri(
            scheme: 'http',
            host: inbound['listen'] as String,
            port: port,
          );
        }
        break;
      }
    }
  }

  Future<Map<String, dynamic>> previewConfiguration() async => {
    'running': false,
    'config': jsonEncode(buildConfig()),
    'assetDirectory': await _assetDirectory(),
    'source': '下次连接配置 · 更新尚未应用到当前连接',
  };

  Future<Map<String, dynamic>> configuration() async {
    try {
      final active = await backend.call('config');
      if (active['running'] == true) {
        if (active['config'] is! String ||
            (active['config'] as String).isEmpty) {
          throw StateError('无法读取运行中配置');
        }
        return {...active, 'source': '运行中配置 · 当前内核快照'};
      }
    } on Object {
      if (connected) rethrow;
    }
    return {
      'running': false,
      'config': jsonEncode(buildConfig()),
      'assetDirectory': await _assetDirectory(),
      'source': '下次启动配置 · 尚未应用',
    };
  }

  Future<void> updateDue() async {
    if (_maintaining || !resourcesEditable || _disposed) return;
    _maintaining = true;
    bool due(int hours, DateTime? attempt) =>
        hours > 0 &&
        (attempt == null ||
            DateTime.now().difference(attempt) >= Duration(hours: hours));
    try {
      for (final s in subscriptions.toList()) {
        if (!resourcesEditable || _disposed) break;
        if (due(s.autoHours, s.attemptedAt)) await updateSubscription(s.id);
      }
      for (final asset in geoAssets.values.toList()) {
        if (!resourcesEditable || _disposed) break;
        if (due(asset.autoHours, asset.attemptedAt)) {
          await updateGeo(asset.kind);
        }
      }
    } on Object {
      error = '自动更新未完成，已保留当前配置。';
      _notify();
    } finally {
      _maintaining = false;
    }
  }

  Future<void> toggle() async {
    if (!canToggle) return;
    await _toggleConnection();
  }

  /// A live switch retains the previous session snapshot until the replacement is saved.
  /// Resource refresh and other UI actions see busy for the entire transition.
  Future<void> switchNode(String id) async {
    if (!resourcesEditable) return;
    final next = profiles.where((p) => p.id == id).firstOrNull;
    if (next == null) return;
    if (connected && routing == RoutingMode.direct) {
      await _change(() async {
        selectedId = id;
      }, allowConnected: true);
      return;
    }
    if (!connected) {
      await select(id);
      return;
    }
    if (_activeProfile?.id == id && !pendingChanges) return;
    await _switchSession(id, routing, '所选节点');
  }

  Future<bool> shutdownForExit() async {
    if (busy || saving) return false;
    _exiting = true;
    _notify();
    var closed = false;
    try {
      if (connected) {
        await _toggleConnection();
        if (status != VpnStatus.disconnected) return false;
      }
      await backend.close();
      _timer?.cancel();
      _maintenance?.cancel();
      latency.stopQueue();
      closed = true;
      return true;
    } finally {
      if (!closed) {
        _exiting = false;
        _notify();
      }
    }
  }

  Future<void> _toggleConnection() async {
    _sessionRevision++;
    error = null;
    if (connected) {
      status = VpnStatus.disconnecting;
      _notify();
      try {
        await backend.call('stop');
        status = VpnStatus.disconnected;
        _activeProfile = null;
        _activeConfig = null;
        _activeHttpProxy = null;
        _sessionId = null;
        uploadRate = downloadRate = 0;
        _log('已断开连接');
      } on Object catch (e) {
        _failure(e);
      }
    } else if (selected != null || routing == RoutingMode.direct) {
      status = VpnStatus.connecting;
      _notify();
      try {
        final selectedAtStart = selected;
        final config = jsonEncode(buildConfig());
        await _startSession(config, await _assetDirectory(), selectedAtStart);
        _log('隧道已启动（远端可达性取决于节点）');
      } on Object catch (e) {
        _failure(e);
      }
    }
    _notify();
  }

  Future<void> _startSession(
    String config,
    String? assets,
    Profile? selectedAtStart,
  ) async {
    final result = await backend.call('start', config, assets);
    if (result['running'] != true) throw StateError('内核未启动');
    upload = download = 0;
    _lastPoll = null;
    _apply(result);
    _rememberSession({
      'running': true,
      'config': config,
      'sessionId': result['sessionId'],
      'assetDirectory': assets,
    }, hint: selectedAtStart);
    status = VpnStatus.connected;
  }

  Future<void> ruleOptions({bool? lan, bool? geo}) => _change(() async {
    bypassLan = lan ?? bypassLan;
    useGeo = geo ?? useGeo;
    if (geoEnabled && selected != null) await _validateSelection();
  }, allowConnected: true);

  Future<void> saveOverrides(List<RouteOverride> next) => _change(() async {
    if (next.map((r) => r.key).toSet().length != next.length) {
      throw const FormatException('已存在相同目标，请编辑原规则');
    }
    overrides = List.unmodifiable(next);
    if (routing == RoutingMode.rules && selected != null) {
      await _validateSelection();
    }
  }, allowConnected: true);

  Future<void> applyRulesNow() async {
    if (!resourcesEditable || !connected || routing != RoutingMode.rules) {
      throw StateError('请先连接并选择规则模式');
    }
    final session = _sessionId;
    final snapshot = _activeConfig;
    final profile = activeProfile;
    if (snapshot == null || session == null || profile == null) {
      throw StateError('无法读取活动会话');
    }
    saving = true;
    _notify();
    try {
      final active = jsonDecode(snapshot) as Map<String, dynamic>;
      final assets = await _assetDirectory();
      final databases = Map.of(geoAssets);
      // Background downloads are staged for the next connection. Keep using
      // the immutable database already referenced by the live table.
      if (geoEnabled && assets != null) {
        final oldRules = (active['routing']['rules'] as List).cast<Map>();
        for (final kind in ['geoip', 'geosite']) {
          final field = kind == 'geoip' ? 'ip' : 'domain';
          final names = oldRules
              .expand((r) => (r[field] as List? ?? []).whereType<String>())
              .where((v) => v.startsWith('ext:$kind-'))
              .map((v) => v.split(':')[1]);
          final file = names.firstOrNull;
          if (file == null || file == databases[kind]!.fileName) continue;
          final digest = GeoStore.fileDigest(kind, file);
          if (digest == null) throw const FormatException('活动规则库文件名无效');
          final info = await backend.call(
            'geo',
            jsonEncode({'kind': kind, 'path': '$assets/$file'}),
          );
          if (info['sha256'] != digest) {
            throw FormatException('活动 $kind 文件已损坏，请用修复后的规则库重新连接');
          }
          databases[kind] = GeoAsset.fromJson({
            ...databases[kind]!.toJson(),
            'fileName': file,
            'tags': info['tags'],
          });
        }
      }
      final updated = ConfigBuilder.build(
        profile,
        platform: platform,
        mode: mode,
        routing: routing,
        bypassLan: bypassLan,
        useGeo: useGeo,
        geoRouting: geoRouting,
        geoAssets: databases,
        overrides: overrides,
      );
      active['routing'] = updated['routing'];
      final config = jsonEncode(active);
      await backend.call(
        'applyRules',
        jsonEncode({'session': session, 'config': config}),
        assets,
      );
      if (_sessionId == session) {
        _activeConfig = config;
        _activeAssets = assets ?? _activeAssets;
        _log('已应用路由规则');
      }
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<void> switchRouting(RoutingMode next) async {
    if (!resourcesEditable || routing == next) return;
    if (!connected) {
      await settings(mode, next);
      return;
    }
    await _switchSession(selectedId, next, next.label);
  }

  Future<void> _switchSession(
    String? nextId,
    RoutingMode nextRouting,
    String label,
  ) async {
    final previousId = selectedId;
    final previous = routing;
    final oldConfig = _activeConfig!;
    final oldAssets = _activeAssets;
    final oldNode = activeProfile;
    _switchingNode = true;
    var stopped = false;
    error = null;
    _notify();
    try {
      selectedId = nextId;
      routing = nextRouting;
      final config = jsonEncode(buildConfig());
      final assets = await _assetDirectory();
      // Resolve the prospective rules before disturbing the active session.
      await _toggleConnection();
      if (status != VpnStatus.disconnected) {
        selectedId = previousId;
        routing = previous;
        return;
      }
      stopped = true;
      status = VpnStatus.connecting;
      _notify();
      await _startSession(config, assets, selected);
      await store.write(_state());
      _log('已切换到$label');
    } on Object catch (e) {
      selectedId = previousId;
      routing = previous;
      if (stopped) {
        try {
          if (connected) await backend.call('stop');
          await _startSession(oldConfig, oldAssets, oldNode);
        } on Object catch (restoreError) {
          _failure('切换失败：$e；恢复原连接失败：$restoreError');
          return;
        }
      }
      error = '未能切换到$label：$e';
    } finally {
      _switchingNode = false;
      _notify();
    }
  }

  void _failure(Object e) {
    status = VpnStatus.failed;
    error = '$e';
    uploadRate = downloadRate = 0;
    _log('连接操作失败，请查看错误详情');
  }

  Future<void> refresh() async {
    if (_polling || busy || _disposed) return;
    _polling = true;
    final revision = _sessionRevision;
    bool stale() => _disposed || busy || revision != _sessionRevision;
    final before = _statusView;
    try {
      final snapshot = await backend.call('status');
      if (stale()) return;
      if (snapshot['running'] == true) {
        if (_activeConfig == null || snapshot['sessionId'] != _sessionId) {
          final config = await backend.call('config');
          if (stale()) return;
          if (config['running'] != true) return;
          _rememberSession(config);
        }
        status = VpnStatus.connected;
      } else if (connected) {
        status = VpnStatus.disconnected;
        _activeProfile = null;
        _activeConfig = null;
        _activeHttpProxy = null;
        _sessionId = null;
        _log('系统已停止 VPN');
      }
      _apply(snapshot);
    } on Object catch (e) {
      if (stale()) return;
      if (connected) _failure(e);
      if (coreVersion == '待检测') error = '$e';
    } finally {
      _polling = false;
      if (!stale() && _statusView != before) _notify();
    }
  }

  // Idle snapshots are identical apart from the private sampling timestamp.
  // Rebuilding every node card on every such snapshot adds no information.
  (VpnStatus, String, String?, Profile?, String?, int, int, int, double, double)
  get _statusView => (
    status,
    coreVersion,
    error,
    _activeProfile,
    _sessionId,
    upload,
    download,
    uptime,
    uploadRate,
    downloadRate,
  );

  void _apply(Map<String, dynamic> snapshot) {
    coreVersion = snapshot['version'] as String? ?? coreVersion;
    final now = DateTime.now();
    final up = (snapshot['upload'] as num?)?.toInt() ?? 0;
    final down = (snapshot['download'] as num?)?.toInt() ?? 0;
    final seconds = _lastPoll == null
        ? 0
        : now.difference(_lastPoll!).inMilliseconds / 1000;
    uploadRate = seconds > 0 ? (up - upload).clamp(0, 1 << 53) / seconds : 0;
    downloadRate = seconds > 0
        ? (down - download).clamp(0, 1 << 53) / seconds
        : 0;
    upload = up;
    download = down;
    uptime = (snapshot['uptime'] as num?)?.toInt() ?? 0;
    _lastPoll = now;
    if (snapshot['error'] is String &&
        (snapshot['error'] as String).isNotEmpty) {
      error = snapshot['error'] as String;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _themeMode.dispose();
    latency.dispose();
    _timer?.cancel();
    _maintenance?.cancel();
    unawaited(backend.close());
    super.dispose();
  }
}

AppController createController() => AppController(
  backend: Platform.isAndroid ? AndroidCoreBackend() : DesktopCoreBackend(),
  store: SecureProfileStore(),
  platform: Platform.operatingSystem,
);
