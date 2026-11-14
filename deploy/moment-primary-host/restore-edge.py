#!/usr/bin/env python3
"""Explicit correction: restore the prior alias behavior, never invoked by application startup."""
import pathlib,json,hashlib,os,fcntl,subprocess,sys
ID='moment-primary-host-preserve-20261114-v1'
BASE=pathlib.Path('/etc/atlas/upgrades/configuration-migrations/moment-identity-switch-20261114-v1')
STORE=BASE.parent/ID;LIVE=pathlib.Path('/etc/nginx/conf.d/happylife.ai.xmkurt.com.conf')
def sha(b):return hashlib.sha256(b).hexdigest()
def atomic(p,b,mode):
 q=p.with_name(p.name+'.'+ID+'.pending');fd=os.open(q,os.O_WRONLY|os.O_CREAT|os.O_EXCL,mode)
 with os.fdopen(fd,'wb') as f:f.write(b);f.flush();os.fsync(f.fileno())
 os.replace(q,p)
STORE.mkdir(parents=True,mode=0o700,exist_ok=True)
with (STORE/'lock').open('a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX);script=sha(pathlib.Path(__file__).read_bytes());journal=STORE/'receipt.json'
 if journal.exists():
  x=json.loads(journal.read_text());assert x['checksum']==script and x['status']=='completed' and sha(LIVE.read_bytes())==x['after'];print(json.dumps({'operationId':ID,'status':'verified'}));sys.exit(0)
 prior=json.loads((BASE/'receipt.json').read_text());assert prior['status']=='completed';row=next(x for x in prior['files'] if x['path']==str(LIVE));before=LIVE.read_bytes();after=(BASE/(LIVE.name+'.before')).read_bytes();assert sha(before)==row['after'] and sha(after)==row['before']
 x={'operationId':ID,'checksum':script,'before':sha(before),'after':sha(after),'status':'prepared'};atomic(STORE/'edge.before',before,0o600);atomic(journal,(json.dumps(x,indent=2)+'\n').encode(),0o600)
 try:
  atomic(LIVE,after,LIVE.stat().st_mode & 0o777);subprocess.run(['nginx','-t'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);subprocess.run(['systemctl','reload','nginx'],check=True);x['status']='completed';atomic(journal,(json.dumps(x,indent=2)+'\n').encode(),0o600)
 except:
  atomic(LIVE,before,LIVE.stat().st_mode & 0o777);x['status']='rolled-back';atomic(journal,(json.dumps(x,indent=2)+'\n').encode(),0o600);raise
 print(json.dumps({'operationId':ID,'status':'completed','primaryDomainUnchanged':'happylife.ai.impx.net','previousAliasBehaviorRestored':True}))
