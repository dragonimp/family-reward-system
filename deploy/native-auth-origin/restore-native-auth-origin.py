#!/usr/bin/env python3
"""One-time, source-controlled native auth origin repair with rollback and journal."""
import fcntl,hashlib,json,os,subprocess
from pathlib import Path
id='moment-native-auth-origin-20261101-v1'
p=Path('/etc/nginx/conf.d/happylife.ai.xmkurt.com.conf');source=Path(__file__).with_name('happylife.ai.xmkurt.com.nginx.conf')
root=Path('/etc/moment-domain-migrations');root.mkdir(mode=0o700,exist_ok=True)
def sha(b):return hashlib.sha256(b).hexdigest()
def write(path,data,mode=0o600):
 t=path.with_name(path.name+'.pending')
 with t.open('xb') as f:os.fchmod(f.fileno(),mode);f.write(data);f.flush();os.fsync(f.fileno())
 os.replace(t,path)
with (root/(id+'.lock')).open('a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX);journal=root/(id+'.json');checksum=sha(Path(__file__).read_bytes()+source.read_bytes())
 if journal.exists():
  r=json.loads(journal.read_text());assert r['checksum']==checksum and r['state']=='completed' and p.read_bytes()==source.read_bytes();print('SKIP: '+id)
 else:
  previous=json.loads((root/'moment-canonical-happylife-20261101-v1-edge.json').read_text())
  expected=next(x['after'] for x in previous['files'] if x['path']==str(p))
  before=p.read_bytes();assert sha(before)==expected,'Nginx changed since reviewed cutover'
  backup=root/(id+'.before.conf');assert not backup.exists();write(backup,before)
  r={'id':id,'checksum':checksum,'state':'prepared','before':expected,'after':sha(source.read_bytes()),'backup':str(backup)};write(journal,json.dumps(r).encode())
  try:
   assert p.read_bytes()==before;write(p,source.read_bytes(),0o644)
   subprocess.run(['nginx','-t'],check=True);subprocess.run(['systemctl','reload','nginx'],check=True)
   assert p.read_bytes()==source.read_bytes();r['state']='completed';write(journal,json.dumps(r).encode());print('APPLIED: '+id)
  except Exception:
   write(p,before,0o644);subprocess.run(['nginx','-t'],check=True);subprocess.run(['systemctl','reload','nginx'],check=True)
   r['state']='rolled-back';write(journal,json.dumps(r).encode());raise
