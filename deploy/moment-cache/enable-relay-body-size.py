#!/usr/bin/env python3
"""Deployment-only, journaled cache route body limit; streaming avoids nginx disk copies."""
import fcntl, hashlib, json, os, subprocess
from pathlib import Path
identity = 'moment-file-cache-nginx-20261101-v1'
config = Path('/etc/nginx/conf.d/happylife.ai.impx.net.conf')
root = Path('/etc/moment-domain-migrations'); root.mkdir(mode=0o700, exist_ok=True)
def digest(data): return hashlib.sha256(data).hexdigest()
def write(path, data, mode=0o600):
    pending = path.with_name(path.name + '.pending')
    with pending.open('xb') as output:
        os.fchmod(output.fileno(), mode); output.write(data); output.flush(); os.fsync(output.fileno())
    os.replace(pending, path)
with (root / (identity + '.lock')).open('a') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    journal = root / (identity + '.json'); checksum = digest(Path(__file__).read_bytes())
    if journal.exists():
        saved = json.loads(journal.read_text())
        assert saved['checksum'] == checksum and saved['state'] == 'completed'
        assert digest(config.read_bytes()) == saved['after']
        print('SKIP: ' + identity)
    else:
        before = config.read_bytes()
        assert digest(before) == '7a6df23c66d315aa819e4a0b4a11a23bcfe8700f3be6880d406be5320eee50c7', 'Reviewed nginx baseline changed'
        needle = b'    location ^~ /api/dear/social/ {\n'
        assert before.count(needle) == 1
        after = before.replace(needle, needle + b'        client_max_body_size 500m;\n', 1)
        backup = root / (identity + '.before.conf'); assert not backup.exists(); write(backup, before)
        saved = dict(id=identity, checksum=checksum, state='prepared', before=digest(before), after=digest(after), backup=str(backup))
        write(journal, json.dumps(saved).encode())
        try:
            assert config.read_bytes() == before; write(config, after, 0o644)
            subprocess.run(['nginx', '-t'], check=True); subprocess.run(['systemctl', 'reload', 'nginx'], check=True)
            assert config.read_bytes() == after; saved['state'] = 'completed'; write(journal, json.dumps(saved).encode())
            print('APPLIED: ' + identity)
        except Exception:
            write(config, before, 0o644); subprocess.run(['nginx', '-t'], check=True); subprocess.run(['systemctl', 'reload', 'nginx'], check=True)
            saved['state'] = 'rolled-back'; write(journal, json.dumps(saved).encode()); raise
