"""Isolated configuration and immutable SQL checks; no live credentials or databases."""
import hashlib,json,runpy,sqlite3,tempfile
from pathlib import Path
from datetime import datetime,timedelta,timezone
root=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory() as temporary:
    work=Path(temporary);db=work/'identity.db'
    with sqlite3.connect(db) as c:
        c.executescript('CREATE TABLE Applications(Id INTEGER,Key TEXT); CREATE TABLE ExternalAuthCredentials(ClientId TEXT,AgentId TEXT,ExpiresAt TEXT,Provider TEXT,Enabled INTEGER,Username TEXT,PrivateKey TEXT); CREATE TABLE SystemApplicationCredentials(ApplicationId INTEGER,ClientId TEXT,Audience TEXT,AllowedScopes TEXT,ExpiresAt TEXT,RevokedAt TEXT,SecretHash TEXT);')
        c.execute('INSERT INTO Applications VALUES(1,?)',('happylife.ai',))
        c.execute('INSERT INTO ExternalAuthCredentials VALUES(?,?,?,?,?,?,?)',('test-key','JQPH54K7SD',None,'apple_apns',1,'production','apns-protected-v1:test'))
        c.execute('INSERT INTO SystemApplicationCredentials VALUES(?,?,?,?,?,?,?)',(1,'test-client','identity.notifications','notifications:send',(datetime.now(timezone.utc)+timedelta(days=1)).isoformat(),None,hashlib.sha256(b'test-secret').hexdigest()))
    auth=work/'auth.json';auth.write_text(json.dumps({'Unrelated':{'saved':1},'Notifications':{'Applications':{'happylife.ai':{'BundleId':'saved-default','Channels':{'custom':{'saved':1}}},'other':{'saved':2}}}}))
    configure=runpy.run_path(str(root.parent/'AgentIdentity/scripts/configure-moment-notifications.py'))['configure']
    configure(str(auth),str(db));first=auth.read_bytes();configure(str(auth),str(db));assert auth.read_bytes()==first
    result=json.loads(first);assert result['Unrelated']=={'saved':1} and result['Notifications']['Applications']['other']=={'saved':2}
    assert result['Notifications']['Applications']['happylife.ai']['BundleId']=='saved-default'
    assert result['Notifications']['Applications']['happylife.ai']['Channels']['app-store-successor']['BundleId']=='net.impx.happylife'
    credential=work/'credential.json';credential.write_text(json.dumps({'ATLAS_RELEASE_CLIENT_ID':'test-client','ATLAS_RELEASE_CLIENT_SECRET':'test-secret','ATLAS_RELEASE_AUTHORITY':'https://identity.example.test'}))
    linko=work/'linko'/'config.json';linko.parent.mkdir();linko.write_text('{"Saved":{"value":true}}')
    configure=runpy.run_path(str(root.parent/'Linko/deploy/configure-moment-notifications.py'))['configure']
    configure(str(linko),str(credential),str(db),'https://linko.example.test','relay.example.test','3478','5349');first=linko.read_bytes();configure(str(linko),str(credential),str(db),'https://linko.example.test','relay.example.test','3478','5349');assert linko.read_bytes()==first
    assert json.loads(first)['Saved']=={'value':True}
    bad=json.loads(credential.read_text());bad['ATLAS_RELEASE_CLIENT_SECRET']='wrong';credential.write_text(json.dumps(bad))
    try:configure(str(linko),str(credential),str(db),'https://linko.example.test','relay.example.test','3478','5349');raise AssertionError('invalid credential accepted')
    except ValueError as e:assert 'secret mismatch' in str(e)
    assert linko.read_bytes()==first
    business=work/'business.db'
    with sqlite3.connect(business) as c:
        c.executescript("CREATE TABLE PhotoDevices(Id TEXT); CREATE TABLE PhotoRequests(Id TEXT,Status TEXT); INSERT INTO PhotoRequests VALUES('waiting','waiting'),('completed','completed');")
        c.executescript((root.parent/'Linko/scripts/data/20261101-moment-connect-file-transfer-v1.sql').read_text())
        assert c.execute('SELECT Id,Status,Transport FROM PhotoRequests ORDER BY Id').fetchall()==[('completed','completed','connect-datachannel-v1'),('waiting','cancelled','connect-datachannel-v1')]
print('PASS: per-channel isolation, preserved configuration, replay skip, credential fingerprint, Connect migration scope')
