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
