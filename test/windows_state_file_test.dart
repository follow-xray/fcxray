import 'dart:convert';
import 'dart:io';
import 'package:fcxray/services/windows_state_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'interrupted Windows staging leaves the last DPAPI commit readable',
    () async {
      final dir = await Directory.systemTemp.createTemp('fcxray-state-test-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/state');
      final store = WindowsStateFile(file);
      expect(await store.read(), isNull);
      const saved = '{"node":"secret-节点","mode":"proxy"}';
      await store.write(saved);
      expect(await store.read(), saved);
      expect(
        utf8.decode(await file.readAsBytes(), allowMalformed: true),
        isNot(contains('secret-')),
      );
      await File('${file.path}.new').writeAsBytes([1, 2, 3], flush: true);
      expect(await WindowsStateFile(file).read(), saved);
      await store.write('{"node":"next"}');
      expect(await store.read(), '{"node":"next"}');
      expect(await File('${file.path}.new').exists(), false);
      await file.writeAsBytes([1, 2, 3]);
      await expectLater(store.read(), throwsA(isA<FileSystemException>()));
    },
    skip: !Platform.isWindows,
  );
}
