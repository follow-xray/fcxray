import 'package:fcxray/services/core_backend.dart';
import 'package:fcxray/services/profile_store.dart';

class MemoryStore implements ProfileStore {
  Map<String, dynamic>? value;
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (fail) throw StateError('store unavailable');
    this.value = value;
  }
}

class FakeBackend implements CoreBackend {
  bool running = false;
  String activeConfig = '';
  String assets = '';
  bool fail = false;
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    String? config,
    String? assetDirectory,
  ]) async {
    if (fail) throw StateError('core failed');
    if (method == 'start') {
      running = true;
      activeConfig = config ?? '';
      assets = assetDirectory ?? '';
    }
    if (method == 'stop') {
      running = false;
      activeConfig = '';
    }
    if (method == 'config') {
      return {
        'running': running,
        'config': activeConfig,
        'assetDirectory': assets,
      };
    }
    return {
      'running': running,
      'version': 'test',
      'upload': 100,
      'download': 200,
      'uptime': 1,
    };
  }

  @override
  Future<void> close() async {}
}
