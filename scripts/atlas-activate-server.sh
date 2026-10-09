#!/usr/bin/env bash
set -euo pipefail

[[ $# == 3 ]] || { echo 'Usage: atlas-activate-server.sh <version> <source-commit> <staging-directory>' >&2; exit 2; }
version="$1"; source_commit="$2"; stage="$3"
[[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ && "$version" != latest ]] || exit 2
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || exit 2
[[ "$stage" == /opt/Atlas/release-staging/family-points-pipeline/"$version" ]] || exit 2
[[ -f "$stage/bundle.json" && -f "$stage/family-points-api.tar.gz" && -f "$stage/family-points-web.tar.gz" ]] || exit 2

atlas_cli=/opt/Atlas/tools/releases-sdk/cli.js
updater=/opt/Atlas/updater/current/Atlas.Updater.dll
app_id=735a18a1-ba4c-4471-b409-279d8014b16a
export ATLAS_RELEASE_BASE_URL=https://home.ai.impx.net
export ATLAS_RELEASE_CREDENTIALS_FILE=/etc/atlas/releases/family-points-publisher.json

python3 - "$stage/bundle.json" "$version" <<'PY'
import json,sys
manifest=json.load(open(sys.argv[1]))
assert manifest['version']==sys.argv[2]
assert {(item['platform'],item['architecture']) for item in manifest['artifacts']}=={('linux','x64'),('web','any'),('server-linux','x64')}
PY

# Migration changes require the separately audited one-time migration workflow.
# Never let an application restart apply new SQL by accident.
python3 - "$stage/family-points-api.tar.gz" /opt/Atlas/downloads/family-points-api-credit/current/migrations <<'PY'
import hashlib,subprocess,sys,tarfile
from pathlib import Path
archive,live=sys.argv[1:]
with tarfile.open(archive,'r:gz') as tar:
    shipped={Path(m.name).name:hashlib.sha256(tar.extractfile(m).read()).hexdigest()
             for m in tar.getmembers() if m.isfile() and m.name.startswith('./migrations/') and m.name.endswith('.sql')}
installed={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in Path(live).glob('*.sql')}
if any(shipped.get(name) != digest for name,digest in installed.items()):
    raise SystemExit('An installed migration changed or disappeared; deployment stopped.')
new=set(shipped)-set(installed)
if new:
    result=subprocess.run(['runuser','-u','postgres','--','psql','-d','family_rewards','-At','-F','|',
                           '-c','SELECT migration_id,sha256 FROM family_reward_schema_migrations'],
                          check=True,capture_output=True,text=True)
    completed=dict(line.split('|',1) for line in result.stdout.splitlines() if '|' in line)
    if any(completed.get(Path(name).stem,'').strip() != shipped[name] for name in new):
        raise SystemExit('New migration lacks a matching audited completion record; deployment stopped.')
PY

node "$atlas_cli" publish-bundle "$app_id" "$stage/bundle.json" > "$stage/atlas-publish-receipt.json"
node "$atlas_cli" list family-points | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["currentVersion"]==sys.argv[1]' "$version"

profile="$stage/application-profile.json"
python3 - "$profile" <<'PY'
import json,os,sys
from pathlib import Path
installed=json.loads(Path('/opt/Atlas/downloads/family-points-api-credit/installation.json').read_text())['profile']['Application']
assert installed['AppCode']=='family-points'
assert installed['ServiceUnit']=='family-reward-api.service'
assert installed['CurrentPointer']=='/opt/Atlas/downloads/family-points-api-credit/current'
fd=os.open(sys.argv[1],os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as file: json.dump(installed,file,separators=(',',':'))
PY

operation="family-pipeline-${version}-api"
/usr/bin/dotnet "$updater" schedule-upgrade "$profile" "$version" "$operation" > "$stage/api-dispatch.json"
for _ in $(seq 1 180); do
  /usr/bin/dotnet "$updater" operation-status "$profile" "$operation" > "$stage/api-status.json"
  state="$(python3 - "$stage/api-status.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
print('completed' if d.get('Succeeded') or d.get('succeeded') else 'failed' if d.get('Terminal') or d.get('terminal') else 'pending')
PY
)"
  [[ "$state" != failed ]] || { echo 'Atlas API upgrade failed; see durable operation journal.' >&2; exit 1; }
  [[ "$state" != completed ]] || break
  sleep 5
done
[[ "$state" == completed ]] || { echo 'Atlas API upgrade did not finish within 15 minutes.' >&2; exit 1; }

site=/var/www/happylife/frontend/static
previous="$(readlink "$site")"
candidate="/var/www/happylife/frontend/releases/$version"
journal="/opt/Atlas/updater-state/family-points-api-credit/family-pipeline-${version}-web.json"
static_profile="$stage/static-profile.json"
python3 - "$static_profile" "$version" "$previous" "$candidate" "$journal" <<'PY'
import hashlib,json,os,sys
from pathlib import Path
output,version,previous,candidate,journal=sys.argv[1:]
assert previous.startswith('/var/www/happylife/frontend/releases/')
assert not Path(candidate).exists() and not Path(journal).exists()
payload={"AtlasOrigin":"https://home.ai.impx.net","AppCode":"family-points","Version":version,
 "Platform":"web","Architecture":"any","FileName":"family-points-web.tar.gz",
 "Site":"/var/www/happylife/frontend/static","Candidate":candidate,
 "Backup":candidate+'-unused-backup',"Journal":journal,
 "ExpectedIndexSha256":hashlib.sha256((Path(previous)/'index.html').read_bytes()).hexdigest(),
 "PublicOrigin":"https://happylife.ai.impx.net","Previous":previous}
fd=os.open(output,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as file: json.dump(payload,file,separators=(',',':'))
PY
/usr/bin/dotnet "$updater" upgrade-static-site "$static_profile" > "$stage/web-status.json"

[[ "$(readlink "$site")" == "$candidate" ]]
curl -fsS https://happylife.ai.impx.net/version.json | python3 -c 'import json,sys; assert json.load(sys.stdin)["version"]==sys.argv[1]' "$version"
curl -fsS https://happylife.ai.impx.net/health >/dev/null
printf '{"summary":"家庭应用 API 和网页已通过 Atlas 发布并验证","evidence":"release=%s source_commit=%s api_operation=%s web_journal=%s"}\n' "$version" "$source_commit" "$operation" "$journal"
