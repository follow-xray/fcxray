#!/usr/bin/env python3
"""Reproducible source build; never downloads an unpinned Xray release binary."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from contextlib import contextmanager
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / 'core.lock.json').read_text())
NATIVE = ROOT / 'native'


def run(args, cwd=ROOT, env=None):
    # CreateProcess does not resolve Flutter's batch entry point as an EXE.
    if os.name == 'nt' and args[0] == 'flutter':
        launcher = shutil.which('flutter.bat')
        if not launcher:
            sys.exit('flutter.bat not found on PATH')
        args = [launcher, *args[1:]]
    print('+', ' '.join(str(a) for a in args), flush=True)
    subprocess.run([str(a) for a in args], cwd=cwd, env=env, check=True)


def source():
    dest = ROOT / 'third_party' / 'Xray-core'
    # Moving the workspace source can leave the previous link dangling.
    if dest.is_symlink() and not dest.exists():
        dest.unlink()
    if not dest.exists():
        candidate = Path(os.environ.get('XRAY_CORE_DIR', ROOT.parent / 'Xray-core'))
        dest.parent.mkdir(parents=True, exist_ok=True)
        if candidate.exists() and os.name != 'nt':
            dest.symlink_to(os.path.relpath(candidate.resolve(), dest.parent), target_is_directory=True)
        else:
            run(['git', 'clone', '--no-checkout', LOCK['repository'], dest])
            run(['git', 'checkout', '--detach', LOCK['commit']], cwd=dest)
    revision = subprocess.check_output(['git', '-C', str(dest), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != LOCK['commit']:
        sys.exit('Xray revision mismatch. Select the pinned source or intentionally update core.lock.json.')
    dirty = subprocess.check_output(['git', '-C', str(dest), 'status', '--porcelain', '--untracked-files=no'], text=True)
    if dirty:
        sys.exit('Xray source has tracked modifications; refusing a non-reproducible build.')
    return dest


@contextmanager
def core_overlay(goos, upstream):
    if goos != 'windows':
        yield []
        return
    # Build against the pinned source, without modifying the user's checkout.
    relative = Path('proxy/tun/tun_windows.go')
    with tempfile.TemporaryDirectory(prefix='fcxray-tun-') as temporary:
        work = Path(temporary)
        patched = work / relative
        patched.parent.mkdir(parents=True)
        patched.write_bytes((upstream / relative).read_bytes().replace(b'\r\n', b'\n'))
        run(['git', '-c', 'core.autocrlf=false', 'apply', '--no-index', ROOT / 'tool/patches/windows-session-tun.patch'], cwd=work)
        overlay = work / 'overlay.json'
        paths = {str(path / relative): str(patched) for path in (upstream, upstream.resolve())}
        overlay.write_text(json.dumps({'Replace': paths}), encoding='utf-8')
        yield ['-overlay=' + str(overlay)]


def core(goos=None, arch=None):
    upstream = source()
    env = os.environ.copy()
    env['GOOS'] = goos or {'Darwin': 'darwin', 'Windows': 'windows', 'Linux': 'linux'}[platform.system()]
    env['GOARCH'] = arch or ('arm64' if platform.machine().lower() in ('arm64', 'aarch64') else 'amd64')
    env['CGO_ENABLED'] = '0'
    name = 'fcxray-core' + ('.exe' if env['GOOS'] == 'windows' else '')
    dest = NATIVE / 'bin' / name
    dest.parent.mkdir(exist_ok=True)
    with core_overlay(env['GOOS'], upstream) as overlay:
        run(['go', 'build', *overlay, '-trimpath', '-ldflags=-s -w', '-o', dest, './cmd/fcxray-core'], cwd=NATIVE, env=env)


def android(target, output=None):
    source()
    env = os.environ.copy()
    sdk = env.get('ANDROID_HOME') or env.get('ANDROID_SDK_ROOT')
    if not sdk and platform.system() == 'Darwin':
        sdk = str(Path.home() / 'Library/Android/sdk')
    if not sdk:
        sys.exit('Set ANDROID_HOME to your Android SDK.')
    env['ANDROID_HOME'] = sdk
    if not env.get('ANDROID_NDK_HOME'):
        versions = sorted((Path(sdk) / 'ndk').iterdir(), key=lambda p: tuple(int(x) for x in p.name.split('.')))
        env['ANDROID_NDK_HOME'] = str(versions[-1])
    tools = ROOT / '.tools' / 'bin'
    tools.mkdir(parents=True, exist_ok=True)
    env['GOBIN'] = str(tools)
    env['PATH'] = str(tools) + os.pathsep + env['PATH']
    mobile = 'golang.org/x/mobile'
    # The version is committed in native/go.mod and shared with gobind's runtime.
    version = subprocess.check_output(['go', 'list', '-m', '-f', '{{.Version}}', mobile], cwd=NATIVE, text=True).strip()
    for name in ('gomobile', 'gobind'):
        run(['go', 'install', f'{mobile}/cmd/{name}@{version}'], cwd=NATIVE, env=env)
    output = output or ROOT / 'android/app/libs/xray.aar'
    output.parent.mkdir(parents=True, exist_ok=True)
    run(['gomobile', 'bind', '-target=' + target, '-androidapi=24', '-trimpath', '-ldflags=-s -w -checklinkname=0', '-o', output, './bridge'], cwd=NATIVE, env=env)


# Android ABI, gomobile architecture and Flutter target are distinct identifiers.
ANDROID_TARGETS = {
    'arm64-v8a': ('android/arm64', 'android-arm64', 2, 183),
    'armeabi-v7a': ('android/arm', 'android-arm', 1, 40),
}


def verify_apk(apk, abi):
    """Reject mixed-ABI APKs and missing or mislabeled native runtimes."""
    _, _, elf_class, machine = ANDROID_TARGETS[abi]
    with zipfile.ZipFile(apk) as archive:
        libraries = [n for n in archive.namelist() if n.startswith('lib/') and n.endswith('.so')]
        architectures = {n.split('/')[1] for n in libraries}
        if architectures != {abi}:
            sys.exit(f'{apk.name}: expected {abi}, found {architectures}')
        for lib in ('libapp.so', 'libflutter.so', 'libgojni.so'):
            with archive.open(f'lib/{abi}/{lib}') as stream:
                header = stream.read(20)
            if (header[:4] != b'\x7fELF' or header[4:6] != bytes((elf_class, 1))
                    or int.from_bytes(header[18:20], 'little') != machine):
                sys.exit(f'{apk.name}: wrong architecture for {lib}')


def tag_apk(tag, abi):
    go_target, flutter_target, _, _ = ANDROID_TARGETS[abi]
    aar = ROOT / 'build/tag-native' / abi / 'xray.aar'
    android(go_target, aar)
    # Strip a conventional version prefix, while allowing non-version tags too.
    label = re.sub(r'^v(?=[0-9])', '', tag)
    label = re.sub(r'[^A-Za-z0-9._+-]+', '-', label).strip('.-')[:100] or 'tag'
    args = ['flutter', 'build', 'apk', '--release', '--split-per-abi',
            f'--target-platform={flutter_target}']
    if re.fullmatch(r'v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?', tag):
        args.append(f'--build-name={tag.removeprefix("v")}')
    run(args, env={**os.environ, 'FCXRAY_ANDROID_AAR': str(aar)})
    apk = ROOT / 'build/app/outputs/flutter-apk' / f'app-{abi}-release.apk'
    verify_apk(apk, abi)
    destination = ROOT / 'build/tag-apks' / f'fcxray-{label}-android-{abi}.apk'
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(apk, destination)
    print(f'Verified APK: {destination}')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.write(f'apk={destination.relative_to(ROOT).as_posix()}\n')
            output.write(f'artifact={destination.stem}\n')


def wintun(arch=None):
    arch = arch or ('arm64' if platform.machine().lower() in ('arm64', 'aarch64') else 'amd64')
    url = 'https://www.wintun.net/builds/wintun-0.14.1.zip'
    digest = '07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51'
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read(4 * 1024 * 1024)
    if hashlib.sha256(data).hexdigest() != digest:
        sys.exit('Wintun checksum mismatch')
    dest = NATIVE / 'bin'
    dest.mkdir(exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        (dest / 'wintun.dll').write_bytes(archive.read(f'wintun/bin/{arch}/wintun.dll'))
        (dest / 'WINTUN-LICENSE.txt').write_bytes(archive.read('wintun/LICENSE.txt'))
    print('Verified Wintun 0.14.1:', arch)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('target', choices=['bootstrap', 'core', 'android-core', 'macos', 'windows', 'apk', 'tag-apk', 'check', 'wintun'])
    parser.add_argument('--goos', choices=['darwin', 'windows', 'linux'])
    parser.add_argument('--arch', choices=['arm64', 'amd64'])
    parser.add_argument('--android-target', default='android/arm64,android/amd64')
    parser.add_argument('--abi', choices=ANDROID_TARGETS)
    parser.add_argument('--tag')
    args = parser.parse_args()
    if args.target == 'bootstrap': source()
    elif args.target == 'wintun': wintun(args.arch)
    elif args.target == 'core': core(args.goos, args.arch)
    elif args.target == 'android-core': android(args.android_target)
    elif args.target == 'check':
        core()
        run(['flutter', 'analyze']); run(['flutter', 'test'])
        with core_overlay(platform.system().lower(), source()) as overlay:
            run(['go', 'test', *overlay, '-race', './...'], cwd=NATIVE)
    elif args.target == 'tag-apk':
        if not args.abi or not args.tag:
            parser.error('tag-apk requires --abi and --tag')
        tag_apk(args.tag, args.abi)
    elif args.target == 'apk':
        android(args.android_target)
        run(['flutter', 'build', 'apk', '--debug', '--target-platform=android-arm64,android-x64'])
        output = ROOT / 'build/app/outputs/flutter-apk'
        shutil.copy2(output / 'app-debug.apk', output / 'fcxray-debug.apk')
        print('APK:', output / 'fcxray-debug.apk')
    elif args.target == 'macos':
        if platform.system() != 'Darwin': sys.exit('macOS builds require macOS + Xcode.')
        core('darwin', args.arch)
        run(['flutter', 'build', 'macos', '--release'])
        app = ROOT / 'build/macos/Build/Products/Release/fcxray.app'
        shutil.copy2(NATIVE / 'bin/fcxray-core', app / 'Contents/MacOS/fcxray-core')
        for notice in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
            shutil.copy2(ROOT / notice, app / 'Contents/Resources' / notice)
        # Development ad-hoc signature. Distribution requires Developer ID + notarization.
        run(['codesign', '--force', '--sign', '-', app / 'Contents/MacOS/fcxray-core'])
        run(['codesign', '--force', '--deep', '--sign', '-', '--entitlements', ROOT / 'macos/Runner/Release.entitlements', app])
    elif args.target == 'windows':
        if platform.system() != 'Windows': sys.exit('Windows Flutter builds require Windows + Visual Studio.')
        core('windows', args.arch)
        wintun(args.arch)
        run(['flutter', 'build', 'windows', '--release'])


if __name__ == '__main__':
    main()
