#!/usr/bin/env python3
"""Create and reclaim owned release scratch directories without following links."""
import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile

PREFIXES = ('family-atlas-check.', 'family-atlas-build.')
MARKER = '.family-release-scratch.json'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('create', 'cleanup'))
    parser.add_argument('value')
    args = parser.parse_args()
    parent = Path(tempfile.gettempdir()).resolve()
    if args.action == 'create':
        if args.value not in PREFIXES:
            parser.error('Unknown scratch purpose')
        path = Path(tempfile.mkdtemp(prefix=args.value, dir=parent))
        (path / MARKER).write_text(json.dumps({'path': str(path), 'uid': os.getuid()}))
        print(path)
        return
    path = Path(args.value)
    if path.is_symlink() or path.parent != parent or not any(path.name.startswith(p) for p in PREFIXES):
        parser.error('Refusing path outside the release scratch scope')
    if not path.exists():
        return
    marker = path / MARKER
    if path.stat().st_uid != os.getuid() or marker.is_symlink() or not marker.is_file():
        parser.error('Scratch ownership evidence missing')
    if json.loads(marker.read_text()) != {'path': str(path), 'uid': os.getuid()}:
        parser.error('Scratch ownership evidence differs')
    if not shutil.rmtree.avoids_symlink_attacks:
        parser.error('This platform cannot safely reclaim scratch directories')
    shutil.rmtree(path)


if __name__ == '__main__':
    main()
