import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

abstract class CoreBackend {
  Future<Map<String, dynamic>> call(
    String method, [
    String? config,
    String? assetDirectory,
  ]);
  Future<void> close();
}

class AndroidCoreBackend implements CoreBackend {
  static const _channel = MethodChannel('com.fcxray.client/core');
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    String? config,
    String? assetDirectory,
  ]) async {
    final raw = await _channel.invokeMethod<String>(method, {
      'config': config,
      'assetDirectory': assetDirectory,
    });
    return jsonDecode(raw!) as Map<String, dynamic>;
  }

  @override
  Future<void> close() async {} // VpnService owns the connection independently.
}

class DesktopCoreBackend implements CoreBackend {
  DesktopCoreBackend({this.executable});
  final String? executable;
  Process? _process;
  IOSink? _input;
  Socket? _socket;
  Directory? _socketDirectory;
  bool _elevated = false;
  bool _closed = false;
  Future<void>? _closing;
  Completer<Socket>? _cancelHandshake;
  Future<void> _queue = Future.value();
  int _sequence = 0;
  final _pending = <int, Completer<Map<String, dynamic>>>{};

  String _corePath() {
    final name = Platform.isWindows ? 'fcxray-core.exe' : 'fcxray-core';
    final candidates = [
      ?executable,
      ?Platform.environment['FCXRAY_CORE'],
      '${File(Platform.resolvedExecutable).parent.path}/$name',
      '${Directory.current.path}/native/bin/$name',
    ];
    final path = candidates.where((p) => File(p).existsSync()).firstOrNull;
    if (path == null) {
      throw StateError('找不到 Xray 内核，请先运行 python3 tool/build.py core');
    }
    return File(path).absolute.path;
  }

  Future<void> _open(bool elevate) async {
    final path = _corePath();
    Stream<List<int>> output;
    late final Process process;
    if (elevate) {
      // Keep the GUI and its Keychain in the user's session. Only the short-lived
      // core receives administrator privileges, after the macOS system prompt.
      final directory = await Directory('/tmp').createTemp('fcxray-');
      _socketDirectory = directory;
      final permission = await Process.run('/bin/chmod', [
        '700',
        directory.path,
      ]);
      if (permission.exitCode != 0) throw StateError('无法保护内核通信目录');
      final socketPath = '${directory.path}/core.sock';
      final listener = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      try {
        final command =
            '${_shellQuote(path)} --socket ${_shellQuote(socketPath)}';
        process = await Process.start('/usr/bin/osascript', [
          '-e',
          'do shell script ${jsonEncode(command)} with administrator privileges',
        ]);
        _process = process;
        process.stderr.listen((_) {});
        process.stdout.listen((_) {});
        // close() may run while Process.start is still resolving.
        if (_closed) throw StateError('内核连接已关闭');
        final cancel = _cancelHandshake = Completer<Socket>();
        final socket = await Future.any<Socket>([
          cancel.future,
          listener.first.then((socket) {
            if (_closed || !identical(_cancelHandshake, cancel)) {
              socket.destroy();
              throw StateError('内核连接已关闭');
            }
            return socket;
          }),
          process.exitCode.then<Socket>(
            (code) => throw StateError('管理员授权被取消或内核无法启动（$code）'),
          ),
        ]).timeout(const Duration(seconds: 90));
        _socket = socket;
        _input = socket;
        output = socket;
      } finally {
        _cancelHandshake = null;
        await listener.close();
      }
    } else {
      process = await Process.start(path, [], runInShell: false);
      _process = process;
      _input = process.stdin;
      output = process.stdout;
      process.stderr.listen((_) {});
    }
    _elevated = elevate;
    output
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (!identical(_process, process)) return;
            try {
              final message = jsonDecode(line) as Map<String, dynamic>;
              final pending = _pending[message['id']];
              if (pending == null || pending.isCompleted) return;
              if (message['error'] != null) {
                pending.completeError(StateError(message['error'] as String));
              } else {
                pending.complete(
                  Map<String, dynamic>.from(message['result'] as Map),
                );
              }
            } on Object {
              _failAll(StateError('内核通信格式错误'));
            }
          },
          onError: (Object e) {
            if (identical(_process, process)) _failAll(e);
          },
          onDone: () {
            if (identical(_process, process)) _failAll(StateError('内核通信已关闭'));
          },
        );
    unawaited(
      process.exitCode.then((code) {
        if (identical(_process, process)) {
          _process = null;
          _input = null;
          _failAll(StateError('Xray 内核已退出（$code）'));
        }
      }),
    );
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";

  void _failAll(Object error) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(error);
    }
    _pending.clear();
  }

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    String? config,
    String? assetDirectory,
  ]) {
    // Serialize polling with startup, elevation, and shutdown.
    final result = _queue.then((_) => _request(method, config, assetDirectory));
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String? config,
    String? assetDirectory,
  ) async {
    if (_closed) throw StateError('内核连接已关闭');
    final elevate =
        Platform.isMacOS &&
        method == 'start' &&
        ((jsonDecode(config!) as Map)['inbounds'] as List).any(
          (i) => i['protocol'] == 'tun',
        );
    if ((elevate && !_elevated) ||
        (_process == null && _socketDirectory != null)) {
      await _closeProcess();
    }
    if (_closed) throw StateError('内核连接已关闭');
    if (_process == null) {
      try {
        await _open(elevate);
      } on Object {
        await _closeProcess();
        rethrow;
      }
    }
    if (_closed) throw StateError('内核连接已关闭');
    final id = ++_sequence;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    try {
      _input!.writeln(
        jsonEncode({
          'id': id,
          'method': method,
          'config': config ?? '',
          'assetDirectory': assetDirectory ?? '',
        }),
      );
      final result = await c.future.timeout(const Duration(seconds: 30));
      if (method == 'stop') await _closeProcess();
      return result;
    } on TimeoutException {
      // A non-responsive status endpoint cannot supervise a live tunnel.
      if (method == 'status' ||
          method == 'probe' ||
          method == 'start' ||
          method == 'stop') {
        await _closeProcess();
      }
      rethrow;
    } on Object {
      if (method == 'status' || method == 'start' || method == 'stop') {
        await _closeProcess();
      }
      rethrow;
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> _closeProcess() async {
    final p = _process;
    try {
      try {
        await _input?.close().timeout(const Duration(seconds: 3));
      } on TimeoutException {
        p?.kill();
      } on IOException {
        // A broken pipe is already closed. Still reap the process.
      } finally {
        _socket?.destroy();
      }
      if (p != null) {
        await p.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            p.kill(ProcessSignal.sigkill);
            return p.exitCode.timeout(const Duration(seconds: 5));
          },
        );
      }
    } finally {
      if (identical(_process, p)) _process = null;
      _input = null;
      _socket = null;
      _elevated = false;
      final directory = _socketDirectory;
      _socketDirectory = null;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    final error = StateError('内核连接已关闭');
    final handshake = _cancelHandshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(error);
    }
    _failAll(error);
    // The in-flight request owns process creation. Wait until ownership is
    // settled before closing pipes; repeated close calls share one cleanup.
    return _closing ??= _queue.then((_) => _closeProcess());
  }
}
