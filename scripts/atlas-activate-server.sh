#!/usr/bin/env bash
set -euo pipefail

[[ $# == 3 ]] || { echo 'Usage: atlas-activate-server.sh <version> <source-commit> <staging-directory>' >&2; exit 2; }
version="$1"; source_commit="$2"; stage="$3"
[[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ && "$version" != latest ]] || exit 2
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || exit 2
[[ "$stage" == /opt/Atlas/release-staging/family-points-pipeline/"$version" ]] || exit 2
[[ -f "$stage/bundle.json" && -f "$stage/family-points-api.tar.gz" && -f "$stage/family-points-web.tar.gz" ]] || exit 2

updater=/opt/Atlas/updater/current/Atlas.Updater.dll
export ATLAS_RELEASE_BASE_URL=https://home.ai.impx.net

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

sudo -n atlas-managed-release publish-bundle family-points "$stage/bundle.json" > "$stage/atlas-publish-receipt.json"
sudo -n atlas-managed-release preflight family-points | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["currentVersion"]==sys.argv[1]' "$version"

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

bash "$stage/install-social-photo-proxy.sh" "$stage/happylife.ai.xmkurt.com.nginx.conf" "$stage"

site=/var/www/happylife/frontend/static
releases_link=/var/www/happylife/frontend/releases
releases_real="$(readlink -f "$releases_link")"
[[ -d "$releases_real" && ! -L "$releases_real" ]] || { echo 'Canonical web release directory missing.' >&2; exit 1; }
previous="$(readlink "$site")"
if [[ "$previous" == "$releases_link/"* ]]; then
  canonical_previous="$(readlink -f "$previous")"
  [[ "$canonical_previous" == "$releases_real/"* && -d "$canonical_previous" ]] || exit 1
  python3 - "$site" "$previous" "$canonical_previous" <<'PY'
import os,sys
site,expected,canonical=sys.argv[1:]
if os.readlink(site)!=expected or not os.path.samefile(expected,canonical):
    raise SystemExit('Static pointer changed before canonicalization')
temporary=f'{site}.canonical-{os.getpid()}'
try:
    os.symlink(canonical,temporary)
    if os.readlink(site)!=expected: raise SystemExit('Static pointer changed during canonicalization')
    os.replace(temporary,site)
finally:
    if os.path.lexists(temporary): os.unlink(temporary)
if os.readlink(site)!=canonical or not os.path.samefile(site,canonical):
    raise SystemExit('Canonical static pointer readback failed')
PY
  previous="$canonical_previous"
fi
[[ "$previous" == "$releases_real/"* && -d "$previous" ]] || exit 1
candidate="$releases_real/$version"
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
