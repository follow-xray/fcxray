#!/usr/bin/env python3
"""Collect dependency license texts for the in-app license page."""
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/licenses'


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    subprocess.run(['go', 'mod', 'download', 'all'], cwd=ROOT / 'native', check=True)
    raw = subprocess.check_output(['go', 'list', '-m', '-json', 'all'], cwd=ROOT / 'native', text=True)
    decoder = json.JSONDecoder()
    entries = []
    missing = []
    while raw.strip():
        module, offset = decoder.raw_decode(raw.lstrip())
        raw = raw.lstrip()[offset:]
        name = module['Path']
        directory = Path(module.get('Replace', module).get('Dir', ROOT / 'native'))
        if module.get('Main'):
            directory = ROOT
        files = sorted(p for p in directory.iterdir() if p.is_file() and
                       (p.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE', 'COPYRIGHT'))))
        # Go's toolchain pseudo-module does not contain a distributable dependency.
        if not files:
            # logex is a test-only dependency of upstream readline and has no
            # license file in its pinned module; it is not linked into the app.
            if name != 'github.com/chzyer/logex': missing.append(name)
            continue
        chunks = [p.read_text(errors='replace') for p in files]
        filename = re.sub(r'[^a-zA-Z0-9_.-]', '_', name) + '.txt'
        (DEST / filename).write_text('\n\n'.join(chunks))
        entries.append({'name': name, 'asset': f'assets/licenses/{filename}'})
    (DEST / 'index.json').write_text(json.dumps(entries, indent=2) + '\n')
    print(f'Collected licenses for {len(entries)} modules.')
    if missing:
        print('No top-level license found (review before distribution):', ', '.join(missing))


if __name__ == '__main__': main()
