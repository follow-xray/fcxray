#!/usr/bin/env python3
"""Opt-in network test of the default database source. No VPN/routes are enabled."""
import hashlib
import json
from pathlib import Path
import urllib.request
from smoke import Helper, ROOT


def main():
    directory = ROOT / 'build/geo-smoke'
    directory.mkdir(parents=True, exist_ok=True)
    helper = Helper()
    try:
        for kind in ('geoip', 'geosite'):
            url = f'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/{kind}.dat'
            target = directory / f'{kind}.dat'
            stage = target.with_suffix('.tmp')
            try:
                with urllib.request.urlopen(url, timeout=30) as response, stage.open('wb') as file:
                    count = 0
                    while chunk := response.read(128 * 1024):
                        count += len(chunk)
                        if count > 64 * 1024 * 1024: raise ValueError('database exceeds 64 MiB')
                        file.write(chunk)
                result = helper.call('geo', {'kind': kind, 'path': str(stage)})
                assert result['sha256'] == hashlib.sha256(stage.read_bytes()).hexdigest()
                assert 'cn' in result['tags']
                stage.replace(target)
                print(f'{kind}: {result["size"]} bytes, {len(result["tags"])} categories, {result["entries"]} entries')
            finally:
                stage.unlink(missing_ok=True)
        config = {'log': {'loglevel': 'none'}, 'outbounds': [{'tag': 'direct', 'protocol': 'freedom'}], 'routing': {'rules': [
            {'type': 'field', 'domain': ['ext:geosite.dat:cn'], 'outboundTag': 'direct'},
            {'type': 'field', 'ip': ['ext:geoip.dat:cn'], 'outboundTag': 'direct'},
        ]}}
        helper.call('validate', config, str(directory))
        print('PASS: real default GeoIP/GeoSite downloads, SHA-256, protobuf and native routing configuration')
    finally:
        helper.close()


if __name__ == '__main__': main()
