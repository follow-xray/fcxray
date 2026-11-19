"""Kill a synthetic GUI or core. Default test uses loopback proxies only.

Use --vm-tun only on a disposable Windows/macOS VM: it uses the app's actual
TUN route/DNS configuration and requires the same privileges as the core.
"""
import argparse
import json
import os
import shutil
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

from smoke import CORE, ROOT, Helper, free_port, read_exact


def owner(transport, folder):
    config = json.loads(sys.stdin.readline())
    helper = Helper(unix=transport == 'unix', socket_dir=folder)
    helper.call('start', config)
    print('ready', flush=True)
    command = sys.stdin.readline().strip()
    if command == 'block':
        # A FIFO with no writer stalls the native file open. The parent test
        # kills this owner while the core cannot get back to its command loop.
        helper.input.write(json.dumps({'id': 2, 'method': 'geo', 'config':
            json.dumps({'kind': 'geoip', 'path': str(folder / 'blocked.dat')})}) + '\n')
        helper.input.flush()
        print('sent', flush=True)
        sys.stdin.readline()
        helper.close()
    elif command == 'kill-core':
        helper.p.kill()
        helper.p.wait(timeout=12)
    else:
        helper.close()


def released(port):
    try:
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', port))
        return True
    except OSError:
        return False


def check_network(baseline):
    # macOS TUN must not edit persistent DNS/proxy configuration. Compare
    # the default network routes and resolver/proxy state with the baseline.
    def read():
        if sys.platform == 'darwin':
            return [subprocess.check_output(cmd) for cmd in (
                ['netstat', '-rn', '-f', 'inet'], ['netstat', '-rn', '-f', 'inet6'],
                ['scutil', '--dns'], ['scutil', '--proxy'])]
        ps = """
$ErrorActionPreference = 'Stop'
@(Get-NetRoute -PolicyStore ActiveStore | Where-Object {
  $_.DestinationPrefix -in @('0.0.0.0/0','::/0') -or $_.InterfaceAlias -like 'fcxray-*'
} | Sort-Object InterfaceIndex,DestinationPrefix,NextHop | Select-Object InterfaceAlias,DestinationPrefix,NextHop,RouteMetric) | ConvertTo-Json -Compress
@(Get-DnsClientServerAddress | Sort-Object InterfaceIndex,AddressFamily | Select-Object InterfaceAlias,AddressFamily,ServerAddresses) | ConvertTo-Json -Compress -Depth 4
@(Get-NetIPInterface | Sort-Object InterfaceIndex,AddressFamily | Select-Object InterfaceAlias,AddressFamily,WeakHostSend,Forwarding) | ConvertTo-Json -Compress
Get-ItemProperty 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Internet Settings' | Select-Object ProxyEnable,ProxyServer,AutoConfigURL | ConvertTo-Json -Compress
"""
        return [subprocess.check_output(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', ps])]

    state = read()
    if sys.platform == 'darwin':
        # Ignore traffic counters and dynamic per-host neighbor/cache routes.
        state[:2] = [sorted((fields[0], fields[1], fields[3]) for line in table.splitlines()
                            if len(fields := line.split()) >= 4 and
                            (fields[0] == b'default' or (b'utun' in fields[3] and b'S' in fields[2])))
                     for table in state[:2]]
    return state if baseline is None else state == baseline


def crash_case(config, port, transport, target, baseline):
    with tempfile.TemporaryDirectory(prefix='fcxray-crash-', dir='/tmp' if transport == 'unix' else None) as tmp:
        folder = Path(tmp)
        p = subprocess.Popen([sys.executable, __file__, '--owner', transport, tmp],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        try:
            p.stdin.write(json.dumps(config) + '\n')
            p.stdin.flush()
            if p.stdout.readline().strip() != 'ready':
                raise RuntimeError('Test session could not start')
            with socket.create_connection(('127.0.0.1', port), timeout=3) as proxy:
                proxy.sendall(b'\x05\x01\x00')
                if read_exact(proxy, 2) != b'\x05\x00':
                    raise AssertionError('SOCKS handshake failed before crash')
            if target == 'busy-gui':
                os.mkfifo(folder / 'blocked.dat', 0o600)
                p.stdin.write('block\n')
                p.stdin.flush()
                if p.stdout.readline().strip() != 'sent':
                    raise RuntimeError('Core request not sent')
                p.kill()
            elif target == 'gui':
                p.kill()  # No graceful IPC stop and no finally block in the owner.
            else:
                p.stdin.write('kill-core\n')
                p.stdin.flush()
            p.wait(timeout=15)
            end = time.monotonic() + 25
            while not released(port) or (baseline is not None and not check_network(baseline)):
                if time.monotonic() >= end:
                    raise AssertionError('The pre-session network state was not restored')
                time.sleep(.2)
            print(f'PASS: {target} killed, {transport} control, listener released' +
                  (', routes/DNS/proxy restored' if baseline is not None else ''), flush=True)
        finally:
            p.stdin.close()
            p.stdout.close()
            if p.poll() is None:
                p.kill()
                p.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vm-tun', action='store_true')
    parser.add_argument('--connectivity-url', default='https://example.com/',
                        help='Reachable DNS/HTTP endpoint to check in --vm-tun mode')
    args = parser.parse_args()
    if not CORE.is_file():
        sys.exit('Build the native core first.')
    if args.vm_tun and sys.platform not in ('darwin', 'win32'):
        sys.exit('--vm-tun requires Windows or macOS')
    if args.vm_tun:
        fixtures = json.loads(subprocess.check_output([shutil.which('dart') or 'dart', 'run', 'tool/config_fixtures.dart'], cwd=ROOT))
        config = fixtures['macos' if sys.platform == 'darwin' else 'windows']
    else:
        config = {'inbounds': [{'protocol': 'socks', 'listen': '127.0.0.1'}],
                  'outbounds': [{'protocol': 'freedom'}]}
    ports = set()
    for inbound in config['inbounds']:
        if inbound['protocol'] in ('socks', 'http'):
            port = free_port()
            while port in ports:
                port = free_port()
            ports.add(port)
            inbound['port'] = port
    port = next(i['port'] for i in config['inbounds'] if i['protocol'] == 'socks')
    baseline = check_network(None) if args.vm_tun else None
    def check_http():
        if args.vm_tun:
            direct = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with direct.open(args.connectivity_url, timeout=15) as response:
                response.read(1)
    check_http()
    for transport in (['stdio', 'unix'] if sys.platform == 'darwin' else ['stdio']):
        for target in (('gui', 'core') if os.name == 'nt' else ('gui', 'core', 'busy-gui')):
            crash_case(config, port, transport, target, baseline)
            check_http()
    probe = Helper()
    try:
        assert probe.call('status')['running'] is False
    finally:
        probe.close()
    print('PASS: cold core start has no active session')


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == '--owner':
        owner(sys.argv[2], Path(sys.argv[3]))
    else:
        main()
