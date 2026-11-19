#!/usr/bin/env python3
"""Local integration test: Flutter config -> client Xray -> VLESS server -> HTTP.
Never enables TUN, modifies routes, or contacts an external server.
"""
import http.client
import http.server
import json
from pathlib import Path
import socket
import struct
import subprocess
import threading
import tempfile
import os

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'native/bin' / ('fcxray-core.exe' if __import__('os').name == 'nt' else 'fcxray-core')


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


class Helper:
    def __init__(self, unix=False, socket_dir=None):
        self.directory = None
        listener = None
        args = [str(CORE)]
        if unix:
            if socket_dir is None:
                self.directory = tempfile.TemporaryDirectory(prefix='xray-smoke-', dir='/tmp')
                socket_dir = self.directory.name
            path = str(Path(socket_dir) / 'core.sock')
            listener = socket.socket(socket.AF_UNIX)
            listener.bind(path); listener.listen(1); listener.settimeout(10)
            args += ['--socket', path]
        self.p = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True)
        self.input, self.output = self.p.stdin, self.p.stdout
        self.connection = None
        if listener:
            self.connection, _ = listener.accept()
            listener.close()
            self.input = self.connection.makefile('w')
            self.output = self.connection.makefile('r')
        self.sequence = 0

    def call(self, method, config=None, asset_directory=None):
        self.sequence += 1
        self.input.write(json.dumps({'id': self.sequence, 'method': method,
                                      'config': json.dumps(config) if config is not None else '', 'assetDirectory': asset_directory or ''}) + '\n')
        self.input.flush()
        # A worker enforces a deadline even when a broken helper never answers.
        result = []
        task = threading.Thread(target=lambda: result.append(self.output.readline()), daemon=True)
        task.start(); task.join(15)
        if task.is_alive():
            raise AssertionError('IPC response timed out')
        message = json.loads(result[0])
        assert message['id'] == self.sequence, message
        assert 'error' not in message, message.get('error')
        return message['result']

    def close(self):
        self.input.close()
        if self.connection:
            self.connection.shutdown(socket.SHUT_RDWR)
            self.output.close(); self.connection.close()
        self.p.stdin.close()
        try:
            self.p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.p.kill(); self.p.wait()
            raise AssertionError('helper failed to exit on parent EOF')
        assert self.p.returncode == 0
        if self.directory: self.directory.cleanup()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        data = b'xray-vless-round-trip-ok'
        self.send_response(200); self.send_header('Content-Length', str(len(data)))
        self.end_headers(); self.wfile.write(data)

    def log_message(self, *args):
        pass


def read_exact(sock, count):
    data = b''
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise AssertionError('unexpected EOF')
        data += chunk
    return data


def main():
    fixtures = json.loads(subprocess.check_output(['dart', 'run', 'tool/config_fixtures.dart'], cwd=ROOT, text=True))
    server, client = Helper(), Helper(unix=os.name != 'nt')
    httpd = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True); thread.start()
    port, socks, http_port = free_port(), free_port(), free_port()
    try:
        for config in fixtures.values():
            assert not client.call('validate', config)['running']
        server.call('start', {'log': {'loglevel': 'none'}, 'inbounds': [{
            'listen': '127.0.0.1', 'port': port, 'protocol': 'vless',
            'settings': {'decryption': 'none', 'clients': [{'id': '11111111-1111-4111-8111-111111111111'}]},
        }], 'outbounds': [{'protocol': 'freedom', 'settings': {'finalRules': [{'action': 'allow', 'ip': ['127.0.0.1/32']}]}}]})
        config = fixtures['proxy']
        config['outbounds'][0]['settings']['vnext'][0]['port'] = port
        config['inbounds'][0]['port'] = socks
        config['inbounds'][1]['port'] = http_port
        for cycle in range(2):
            assert client.call('start', config)['running']
            with socket.create_connection(('127.0.0.1', socks), timeout=5) as connection:
                connection.sendall(b'\x05\x01\x00'); assert read_exact(connection, 2) == b'\x05\x00'
                connection.sendall(b'\x05\x01\x00\x01' + socket.inet_aton('127.0.0.1') + struct.pack('!H', httpd.server_port))
                assert read_exact(connection, 4) == b'\x05\x00\x00\x01'
                read_exact(connection, 6)
                connection.sendall(b'GET / HTTP/1.0\r\nHost: localhost\r\n\r\n')
                response = http.client.HTTPResponse(connection)
                response.begin()
                assert response.read() == b'xray-vless-round-trip-ok'
                response.close()
            status = client.call('status')
            assert status['upload'] > 0 and status['download'] > 0, status
            assert not client.call('stop')['running']
        # Closing a running helper through EOF must release its listeners too.
        client.call('start', config)
    finally:
        client.close(); server.close(); httpd.shutdown(); httpd.server_close()
    for p in (socks, http_port, port):
        with socket.socket() as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(('127.0.0.1', p))
    print('PASS: Android/Windows/macOS configs, VLESS transfer, real counters, restart, and EOF cleanup')


if __name__ == '__main__':
    main()
