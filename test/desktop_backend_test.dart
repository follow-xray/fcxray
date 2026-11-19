import 'dart:convert';
import 'package:fcxray/services/node_latency.dart';
import 'package:fcxray/models/profile.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcxray/services/core_backend.dart';

void main() {
  final executable =
      '${Directory.current.path}/native/bin/fcxray-core${Platform.isWindows ? '.exe' : ''}';
  test(
    'malformed response completes its caller without waiting for the IPC timeout',
    () async {
      final dir = await Directory.systemTemp.createTemp('fcxray-ipc-');
      addTearDown(() => dir.delete(recursive: true));
      final script = File('${dir.path}/helper');
      await script.writeAsString("""#!/bin/sh
read -r request
echo '{"id":1,"result":[]}'
cat >/dev/null
""");
      await Process.run('chmod', ['700', script.path]);
      final backend = DesktopCoreBackend(executable: script.path);
      addTearDown(backend.close);
      await expectLater(
        backend.call('status').timeout(const Duration(seconds: 5)),
        throwsStateError,
      );
    },
    skip: Platform.isWindows,
  );
  test(
    'close during core creation drains pending calls and releases ownership',
    () async {
      final backend = DesktopCoreBackend(executable: executable);
      final starting = backend.call('status');
      final rejected = expectLater(starting, throwsStateError);
      // _request has entered Process.start but the process handle is not yet delivered.
      await Future<void>.value();
      final stopping = backend.close();
      expect(identical(stopping, backend.close()), true);
      await stopping;
      await rejected;
      await expectLater(backend.call('status'), throwsStateError);
    },
    skip: !File(executable).existsSync(),
  );
  test(
    'desktop IPC reports native failures, recovers, and releases listeners',
    () async {
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final backend = DesktopCoreBackend(executable: executable);
      addTearDown(backend.close);
      expect((await backend.call('status'))['running'], false);
      await expectLater(
        backend.call('start', '{"inbounds":[{"protocol":"unsupported"}]}'),
        throwsStateError,
      );
      expect((await backend.call('status'))['running'], false);
      final config = jsonEncode({
        'log': {'loglevel': 'none'},
        'inbounds': [
          {'listen': '127.0.0.1', 'port': port, 'protocol': 'socks'},
        ],
        'outbounds': [
          {'protocol': 'freedom'},
        ],
      });
      expect((await backend.call('start', config))['running'], true);
      final before = await backend.call('config');
      final candidate = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => candidate.close(force: true));
      var contacted = false;
      candidate.listen((request) {
        contacted = true;
        request.response.statusCode = 403;
        request.response.close();
      });
      final node = Profile.create('Other subscription', {
        'protocol': 'http',
        'settings': {'address': '127.0.0.1', 'port': candidate.port},
      });
      await expectLater(measureNodeLatency(node), throwsStateError);
      expect(contacted, true);
      expect(await backend.call('config'), before);
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      socket.add([5, 1, 0]);
      expect((await socket.first).take(2), [5, 0]);
      socket.destroy();
      expect((await backend.call('stop'))['running'], false);
      await backend.call('start', config);
      await backend.close();
      final check = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await check.close();
    },
    skip: File(executable).existsSync()
        ? false
        : 'Build native helper with python tool/build.py core first',
  );
}
