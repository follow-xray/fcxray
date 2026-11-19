import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/profile.dart';
import 'core_backend.dart';

Future<int> measureNodeLatency(Profile profile) async {
  final outbound = jsonEncode(profile.outbound);
  if (Platform.isAndroid) {
    const channel = MethodChannel('com.fcxray.client/core');
    return await channel.invokeMethod<int>('latency', {'outbound': outbound}) ??
        -1;
  }
  // This helper only handles this probe. It never receives the session's
  // config, TUN descriptor, elevation request, start, or stop command.
  final helper = DesktopCoreBackend();
  try {
    final response = await helper.call('probe', outbound);
    return response['ms'] as int;
  } finally {
    await helper.close();
  }
}

class NodeLatency extends ChangeNotifier {
  NodeLatency({this.measure = measureNodeLatency, int? concurrency})
    : concurrency = concurrency ?? (Platform.isAndroid ? 1 : 3);
  final Future<int> Function(Profile) measure;
  final int concurrency;
  // Results expire with a replaced profile, including edits retaining its ID.
  final _results = Expando<int>();
  final _testing = <Profile>{};
  bool busy = false, stopping = false, _disposed = false;
  int completed = 0, total = 0;

  int? result(Profile p) => _results[p];
  String label(Profile p) {
    if (p.isUtility) return '不适用';
    if (_testing.contains(p)) return '测试中…';
    final ms = result(p);
    if (ms == null) return '未测试';
    return ms > 0 ? '$ms ms' : '测试失败';
  }

  List<Profile> sorted(List<Profile> profiles) {
    final order = {for (var i = 0; i < profiles.length; i++) profiles[i]: i};
    int rank(Profile p) {
      final ms = result(p);
      return ms != null && ms > 0 ? ms : 0x7fffffff;
    }

    return [...profiles]..sort((a, b) {
      final diff = rank(a).compareTo(rank(b));
      return diff == 0 ? order[a]!.compareTo(order[b]!) : diff;
    });
  }

  Future<void> run(Iterable<Profile> profiles) async {
    if (busy || _disposed) return;
    final jobs = profiles.where((p) => !p.isUtility).toSet().toList();
    if (jobs.isEmpty) return;
    busy = true;
    stopping = false;
    completed = 0;
    total = jobs.length;
    var next = 0;
    Future<void> worker() async {
      while (!_disposed && !stopping && next < jobs.length) {
        final profile = jobs[next++];
        _testing.add(profile);
        notifyListeners();
        try {
          _results[profile] = await measure(profile);
        } on Object {
          _results[profile] = -1;
        } finally {
          completed++;
          _testing.remove(profile);
          if (!_disposed) notifyListeners();
        }
      }
    }

    try {
      await Future.wait(List.generate(concurrency, (_) => worker()));
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void stopQueue() {
    stopping = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
