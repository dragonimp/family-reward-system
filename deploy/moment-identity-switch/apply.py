#!/usr/bin/env python3
"""Explicit, journaled deployment configuration. Never invoked by application startup."""
import pathlib,hashlib,json,subprocess,fcntl,os,sys
ROOT=pathlib.Path(__file__).parent;ID='moment-identity-switch-20261114-v1';STORE=pathlib.Path('/etc/atlas/upgrades/configuration-migrations')/ID
ENV=pathlib.Path('/etc/agentidentity/gateway-service.env');EDGE=pathlib.Path('/etc/nginx/conf.d/happylife.ai.xmkurt.com.conf');RULE='OAuth__NativeSso__AllowedTargets__linko-moment.ai__0';VALUE='linko.ai'
def sha(b):return hashlib.sha256(b).hexdigest()
def atomic(p,data,mode):
 q=p.with_name(p.name+'.'+ID+'.pending');fd=os.open(q,os.O_CREAT|os.O_EXCL|os.O_WRONLY,mode)
 with os.fdopen(fd,'wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
 os.replace(q,p)
def main(action):
 assert action in ['preflight','apply','verify']
 STORE.mkdir(mode=0o700,parents=True,exist_ok=True)
 digest=sha(pathlib.Path(__file__).read_bytes()+(ROOT/'happylife.ai.xmkurt.com.nginx.conf').read_bytes())
 with (STORE/'lock').open('a') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX);journal=STORE/'receipt.json'
  if journal.exists():
   record=json.loads(journal.read_text());assert record['checksum']==digest,'Executed configuration script changed'
   assert record['status']=='completed','Inspect prepared operation; do not replay'
   for x in record['files']:assert sha(pathlib.Path(x['path']).read_bytes())==x['after'],'Applied configuration drifted'
   print(json.dumps({'status':'verified','operationId':ID,'files':len(record['files'])}));return
  assert action!='verify','Configuration has not been applied'
  assert not ENV.is_symlink() and not EDGE.is_symlink(), "Configuration aliases require explicit review"
  beforeEnv=ENV.read_bytes();lines=beforeEnv.decode().splitlines();existing=[s.partition('=')[2].strip('"') for s in lines if s.startswith(RULE+'=')];assert not existing or existing==[VALUE],'Existing Moment SSO rule conflicts'
  afterEnv=beforeEnv if existing else (beforeEnv.rstrip(b'\n')+b'\n'+(RULE+'='+VALUE+'\n').encode())
  afterEdge=(ROOT/'happylife.ai.xmkurt.com.nginx.conf').read_bytes();beforeEdge=EDGE.read_bytes();assert b'server_name happylife.ai.xmkurt.com;' in beforeEdge
  files=[{'path':str(p),'before':sha(old),'after':sha(new),'mode':p.stat().st_mode & 0o777} for p,old,new in [(ENV,beforeEnv,afterEnv),(EDGE,beforeEdge,afterEdge)]]
  baseline=STORE/'preflight.json';candidate={'operationId':ID,'checksum':digest,'files':files}
  if action=='preflight':
   if baseline.exists():assert json.loads(baseline.read_text())==candidate,'Preflight baseline drifted'
   else:atomic(baseline,(json.dumps(candidate,indent=2)+'\n').encode(),0o600)
   print(json.dumps(candidate));return
  assert baseline.exists() and json.loads(baseline.read_text())==candidate,'Run preflight for the exact baseline first'
  for p,old in [(ENV,beforeEnv),(EDGE,beforeEdge)]:atomic(STORE/(p.name+'.before'),old,0o600)
  record={**candidate,'status':'prepared'};atomic(journal,(json.dumps(record,indent=2)+'\n').encode(),0o600)
  try:
   atomic(ENV,afterEnv,files[0]['mode']);atomic(EDGE,afterEdge,files[1]['mode']);subprocess.run(['nginx','-t'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
   subprocess.run(['systemctl','reload','nginx'],check=True);record['status']='completed';atomic(journal,(json.dumps(record,indent=2)+'\n').encode(),0o600)
  except:
   atomic(ENV,beforeEnv,files[0]['mode']);atomic(EDGE,beforeEdge,files[1]['mode']);record['status']='rolled-back';atomic(journal,(json.dumps(record,indent=2)+'\n').encode(),0o600);raise
  print(json.dumps({'operationId':ID,'status':'completed','userCenterRestartRequired':True,'originalApplicationAndLegacyDomainUnchanged':True}))
if __name__=='__main__':main(sys.argv[1])
