import json,uuid,time,urllib.request,urllib.error,concurrent.futures,os
base=os.environ['DINING_SOCIAL_TEST_ORIGIN'] + '/api/dining/gatherings'
u=[str(uuid.uuid4()) for _ in range(5)]
def call(path='', user=None, data=None, expected=200):
 headers={} if user is None else {'X-Fixture-User':user}
 if data is not None:headers['Content-Type']='application/json'
 req=urllib.request.Request(base+path,headers=headers,data=None if data is None else json.dumps(data).encode())
 try:
  with urllib.request.urlopen(req,timeout=5) as r:status=r.status; raw=r.read()
 except urllib.error.HTTPError as e:status=e.code;raw=e.read()
 assert status==expected,(path,status,expected,raw)
 return json.loads(raw) if raw and status==200 else None
for n in range(40):
 try:call(expected=401);break
 except urllib.error.URLError:time.sleep(.25)
else:raise RuntimeError('Harness did not start')
id=str(uuid.uuid4());p={'id':id,'restaurantId':'amap:fixture','restaurantName':'测试餐厅'}
assert call(user=u[0],data=p)['id']==id
assert call(user=u[0].upper(),data=p)['id']==id
call(user=u[0],data={**p,'restaurantName':'different'},expected=409)
call('/'+id,u[4],expected=404)
host_row=call('/'+id,u[0])
code=host_row['shortCode']
assert len(code)==6 and code.isascii() and code.isdecimal()
from datetime import datetime
assert (datetime.fromisoformat(host_row['codeExpiresAt'])-datetime.fromisoformat(host_row['createdAt'])).total_seconds()==1200
assert call('/'+id,u[1],expected=404) is None
with concurrent.futures.ThreadPoolExecutor() as pool:
 assert all(x['id']==id for x in pool.map(lambda who:call('/join',who,{'code':code.upper()}),u[1:4]))
call('/join',u[1],{'code':host_row['joinCode'].upper()})
assert len(call('/'+id,u[0])['members'])==4
assert call('/'+id,u[1])['joinCode'] is None and call('/'+id,u[1])['shortCode'] is None
call('/'+id+'/end',u[1],{},404)
for who in u[:3]:call('/'+id.upper()+'/confirm',who,{},204)
call('/'+id+'/confirm',u[0],{},204)
call('/'+id+'/end',u[0],{},204)
call('/'+id+'/end',u[0],{},204)
call('/join',u[4],{'code':code},404)
call('/'+id+'/confirm',u[3],{},409)
row=call('/'+id,u[1]); assert row['endedAt'] and row['joinCode'] is None
assert sum(bool(m['confirmedAt']) for m in row['members'])==3
assert call(user=u[4])==[]
print('PASS: authenticated four-member gathering, case-insensitive UUIDs, retry safety, membership and host authorization, end and preserved confirmations')
base=os.environ['DINING_SOCIAL_TEST_ORIGIN'] + '/api/dining/circle'
def put(path, user, data, expected=204):
 req=urllib.request.Request(base+path,method='PUT',headers={'X-Fixture-User':user,'Content-Type':'application/json'},data=json.dumps(data).encode())
 try:
  with urllib.request.urlopen(req,timeout=5) as r:status=r.status
 except urllib.error.HTTPError as e:status=e.code
 assert status==expected,(path,status,expected)
assert len(call('/buddies',u[0]))==2
pid=str(uuid.uuid4())
post={**p,'id':pid,'visibility':'selected','buddyIds':[u[1].upper()]}
call('/posts',u[0],post)
call('/posts',u[0],post)
assert call('/posts',u[1])==[]
put('/buddies/'+u[1],u[0],{'enabled':True})
assert call('/posts',u[1])==[]
put('/buddies/'+u[0].upper(),u[1],{'enabled':True})
assert len(call('/posts',u[1]))==1
assert call('/posts',u[2])==[] and call('/posts',u[4])==[]
put('/posts/'+pid+'/actions/like',u[1],{'enabled':True})
put('/posts/'+pid+'/actions/like',u[1],{'enabled':True})
assert call('/posts',u[0])[0]['likes']==1

comment={'id':str(uuid.uuid4()),'body':'测试评论'}
call('/posts/'+pid+'/comments',u[2],comment,404)
call('/posts/'+pid+'/comments',u[1],comment,204)
call('/posts/'+pid+'/comments',u[1],comment,204)
assert call('/posts',u[1])[0]['comments']==['测试评论']
put('/posts/'+pid+'/actions/save',u[1],{'enabled':True})
put('/posts/'+pid+'/actions/want',u[1],{'enabled':True})
assert call('/restaurants',u[1])[0]['saved'] and call('/restaurants',u[1])[0]['wanted']
put('/posts/'+pid+'/visibility',u[1],{'visibility':'private'},404)
put('/posts/'+pid+'/visibility',u[0],{'visibility':'private'})
assert call('/posts',u[1])==[]
put('/posts/'+pid+'/visibility',u[0],{'visibility':'buddies'})
assert len(call('/posts',u[1]))==1
put('/buddies/'+u[0],u[1],{'enabled':False})
assert call('/posts',u[1])==[] and call('/restaurants',u[1])==[]
print('PASS: targeted visibility, mutual consent, immediate revocation, private scope, action deduplication and author authorization')

put('/buddies/'+u[0],u[1],{'enabled':True})
nextid=str(uuid.uuid4())
base=os.environ['DINING_SOCIAL_TEST_ORIGIN'] + '/api/dining/gatherings'
call(user=u[0],data={**p,'id':nextid})
base=os.environ['DINING_SOCIAL_TEST_ORIGIN'] + '/api/dining/circle'
call('/invitations',u[0],{'gatheringId':nextid,'buddyId':u[4]},404)
call('/invitations',u[0],{'gatheringId':nextid,'buddyId':u[1]},204)
put('/invitations/'+nextid,u[4],{'accept':True},404)
put('/invitations/'+nextid,u[1],{'accept':True})
put('/invitations/'+nextid,u[1],{'accept':True})
assert call('/invitations',u[1])[0]['status']=='accepted'
base=os.environ['DINING_SOCIAL_TEST_ORIGIN'] + '/api/dining/gatherings'
assert len(call('/'+nextid,u[1])['members'])==2
print('PASS: invitation ownership, mutual consent, acceptance and retry safety')

import subprocess
active=call('/'+nextid,u[0])
subprocess.run(['psql', os.environ['FAMILY_REWARD_DB_DSN'], '-X', '-v', 'ON_ERROR_STOP=1', '-c',
    f"UPDATE dining_gatherings SET created_at=now()-interval '21 minutes' WHERE id='{nextid}'"], check=True)
expired=call('/'+nextid,u[0])
assert expired['joinExpired'] and expired['joinCode'] is None
call('/join',u[4],{'code':active['shortCode']},404)
assert expired['shortCode'] is None
