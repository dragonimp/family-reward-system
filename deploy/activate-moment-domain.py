#!/usr/bin/env python3
"""Explicit Atlas deployment step, never application startup. CAS + backups + durable journal."""
import fcntl, hashlib, json, os, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ID = 'moment-canonical-happylife-20261101-v1'
BASELINES = {
 'happylife.ai.impx.net': '26d4523d283cff1837940b63601a339b1963de2c7c4c35060457c5d91c230182',
 'linko.ai.impx.net': 'b4ab59d746e7c6d33e61a8fda8c370eeb148396cc45b4a003ce76ef0a16f1e19',
 'happylife.ai.xmkurt.com': '2f4c57f399e95942f059f592864d958b3956324cb328bf4060102261a004b4c4',
}
def sha(b): return hashlib.sha256(b).hexdigest()
def atomic(path, value, mode=0o600):
 temp = path.with_name(path.name+'.moment-pending')
 with temp.open('xb') as f:
  os.fchmod(f.fileno(),mode); f.write(value); f.flush(); os.fsync(f.fileno())
 os.replace(temp,path)
def run(*args): subprocess.run(args,check=True,stdout=subprocess.DEVNULL)
def main(action):
 if action not in ('transport','edge'): raise ValueError('transport or edge required')
 journal_root=Path('/etc/moment-domain-migrations');journal_root.mkdir(mode=0o700,exist_ok=True)
 checksum=sha(Path(__file__).read_bytes()+b''.join(p.read_bytes() for p in sorted(ROOT.glob('*.conf')))+ (ROOT/'configure-turn.sh').read_bytes())
 with (journal_root/(ID+'.lock')).open('a') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX)
  journal=journal_root/(ID+'-'+action+'.json')
  if journal.exists():
   record=json.loads(journal.read_text())
   if record['checksum']!=checksum: raise ValueError('Executed migration changed')
   if record['status']!='completed': raise ValueError('Inspect and recover prepared operation before retry')
   for item in record['files']:
    if sha(Path(item['path']).read_bytes())!=item['after']: raise ValueError('Applied configuration drifted')
   print('SKIP: '+ID+' '+action);return
  updates={}
  if action=='edge':
   for host in BASELINES:
    live=Path('/etc/nginx/conf.d/'+host+'.conf')
    if sha(live.read_bytes()) != BASELINES[host]: raise ValueError('Nginx baseline changed: '+host)
    updates[live]=(ROOT/(host+'.nginx.conf')).read_bytes()
  else:
   path=Path('/etc/linko/atlas-installation.json');data=json.loads(path.read_text())
   connect=data['Linko']['Connect']
   for key in ('AllowedOrigins','StunUrls','TurnUrls'):
    values=connect[key]
    if not any('linko.ai.impx.net' in x for x in values): raise ValueError('Unexpected saved Connect binding')
    connect[key]=[x.replace('linko.ai.impx.net','happylife.ai.impx.net') for x in values]
   updates[path]=(json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode()
  extra=[] if action=='edge' else [Path(p) for p in ['/etc/turnserver.conf','/etc/coturn/linko-fullchain.pem','/etc/coturn/linko-privkey.pem','/etc/atlas/environments/linko/turn.env','/etc/systemd/system/linko-api.service.d/turn.conf']]
  files=[]
  for i,path in enumerate([*updates,*extra]):
   if path.is_symlink() or not path.is_file(): raise ValueError('Canonical existing file required: '+str(path))
   before=path.read_bytes();backup=journal_root/(ID+'-'+action+'-'+str(i)+'.before')
   if backup.exists(): raise ValueError('Existing rollback copy requires review')
   atomic(backup,before)
   files.append({'path':str(path),'before':sha(before),'backup':str(backup),'mode':path.stat().st_mode & 0o777})
  record={'id':ID,'action':action,'checksum':checksum,'status':'prepared','files':files}
  atomic(journal,(json.dumps(record,indent=2)+'\n').encode())
  try:
   for item in files:
    path=Path(item['path'])
    if sha(path.read_bytes())!=item['before']: raise ValueError('Concurrent configuration change')
    if path in updates: atomic(path,updates[path],item['mode'])
   if action=='edge':run('nginx','-t');run('systemctl','reload','nginx')
   else:run('bash',str(ROOT/'configure-turn.sh'))
   for item in files:item['after']=sha(Path(item['path']).read_bytes())
   record['status']='completed';atomic(journal,(json.dumps(record,indent=2)+'\n').encode())
  except Exception:
   for item in files:atomic(Path(item['path']),Path(item['backup']).read_bytes(),item['mode'])
   if action=='edge':run('nginx','-t');run('systemctl','reload','nginx')
   else:run('systemctl','daemon-reload');run('systemctl','restart','coturn')
   record['status']='rolled-back';atomic(journal,(json.dumps(record,indent=2)+'\n').encode());raise
  print('APPLIED: '+ID+' '+action+'; backup and independent file checks retained')
if __name__=='__main__':main(*sys.argv[1:])
