#!/usr/bin/env python3
"""Provision the successor main/share profiles with the existing local distribution identity."""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess

source = Path(__file__).with_name('provision-moment-apple-identifiers-v2.py')
spec = importlib.util.spec_from_file_location('moment_apple', source)
apple = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apple)
team_root = Path.home() / '.local/share/apple-signing/JQPH54K7SD'
expected = json.loads((team_root / 'setup.json').read_text())['identitySha1']
certificates = [item for item in apple.api('certificates?limit=200')['data']
    if hashlib.sha1(base64.b64decode(item['attributes']['certificateContent'])).hexdigest().upper() == expected]
assert len(certificates) == 1 and certificates[0]['attributes']['certificateType'] == 'DISTRIBUTION'
import sys
kind = sys.argv[1]
assert kind in ('main', 'share')
bundle_id = 'net.impx.happylife' + ('.share' if kind == 'share' else '')
bundle = apple.find_bundle(bundle_id)
assert bundle is not None
name = f'Linko Moment Successor {kind.title()} App Store 20261030'

def existing():
    result = apple.api('profiles?limit=200')
    if result.get('links', {}).get('next'):
        raise RuntimeError('Profile listing requires pagination; do not create without complete reconciliation')
    matches = [p for p in result['data'] if p['attributes']['name'] == name and p['attributes']['profileState'] == 'ACTIVE']
    assert len(matches) <= 1
    return matches[0] if matches else None

profile = existing()
if profile is None:
    try:
        apple.api('profiles', 'POST', {'data': {'type': 'profiles',
            'attributes': {'name': name, 'profileType': 'IOS_APP_STORE'},
            'relationships': {
                'bundleId': {'data': {'type': 'bundleIds', 'id': bundle['id']}},
                'certificates': {'data': [{'type': 'certificates', 'id': certificates[0]['id']}]}}}})
    except Exception:
        if existing() is None:
            raise
    profile = existing()
assert profile is not None
raw = base64.b64decode(profile['attributes']['profileContent'])
path = team_root / f'linko-moment-successor-{kind}-20261030.mobileprovision'
os.umask(0o077)
path.write_bytes(raw)
data = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(path)], stderr=subprocess.DEVNULL))
assert data['TeamIdentifier'] == ['JQPH54K7SD']
assert data['Entitlements']['application-identifier'] == 'JQPH54K7SD.' + bundle_id
assert 'group.net.impx.happylife' in data['Entitlements'].get('com.apple.security.application-groups', [])
if kind == 'main':
    assert data['Entitlements'].get('aps-environment') == 'production'
assert not data.get('ProvisionedDevices') and not data['Entitlements'].get('get-task-allow')
assert any(hashlib.sha1(cert).hexdigest().upper() == expected for cert in data['DeveloperCertificates'])
for folder in ['Library/MobileDevice/Provisioning Profiles', 'Library/Developer/Xcode/UserData/Provisioning Profiles']:
    directory = Path.home() / folder
    directory.mkdir(parents=True, exist_ok=True)
    (directory / (data['UUID'] + '.mobileprovision')).write_bytes(raw)
receipt = {'operationId': f'20261030-moment-successor-{kind}-profile-v1',
    'scriptSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'profileId': profile['id'], 'profileUuid': data['UUID'], 'bundleId': bundle_id,
    'profileType': 'IOS_APP_STORE', 'existingCertificateMatched': True,
    'expirationUtc': data['ExpirationDate'].isoformat() + 'Z', 'profileSha256': hashlib.sha256(raw).hexdigest()}
output = Path(__file__).resolve().parent.parent / f'bin/release-receipts/moment-successor-{kind}-profile.json'
output.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt))
