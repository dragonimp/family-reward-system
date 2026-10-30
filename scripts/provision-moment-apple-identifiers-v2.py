#!/usr/bin/env python3
"""Register Moment successor bundle identifiers with the existing team API identity.

Only identifier/capability operations are supported here. Release uploads and
TestFlight distribution continue through atlas-managed-release.
"""
import datetime
import hashlib
import json
from pathlib import Path
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

TEAM = 'JQPH54K7SD'
CONFIG = Path.home() / '.local/share/apple-signing' / TEAM / 'api.json'
RECEIPT = Path(__file__).resolve().parent.parent / 'bin/release-receipts/moment-successor-identifiers-v2.json'
TARGETS = {
    'net.impx.happylife': ('Linko Moment', ['PUSH_NOTIFICATIONS', 'APP_GROUPS']),
    'net.impx.happylife.watchkitapp': ('Linko Moment Watch', []),
    'net.impx.happylife.share': ('Linko Moment Share', ['APP_GROUPS']),
}


def api(path, method='GET', body=None):
    config = json.loads(CONFIG.read_text())
    if config['teamId'] != TEAM:
        raise RuntimeError('Signing team mismatch')
    now = int(time.time())
    token = jwt.encode({'iss': config['issuerId'], 'iat': now, 'exp': now + 300,
                        'aud': 'appstoreconnect-v1'}, Path(config['privateKeyPath']).read_text(),
                       algorithm='ES256', headers={'kid': config['keyId']})
    request = urllib.request.Request('https://api.appstoreconnect.apple.com/v1/' + path,
        method=method, headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'},
        data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            data = response.read()
            return json.loads(data) if data else {}
    except urllib.error.HTTPError as error:
        data = json.load(error)
        details = [(item.get('code'), item.get('detail')) for item in data.get('errors', [])]
        raise RuntimeError(f'Apple HTTP {error.code}: {details}') from None


def find_bundle(identifier):
    result = api('bundleIds?' + urllib.parse.urlencode({'filter[identifier]': identifier, 'limit': 200}))
    matches = [item for item in result.get('data', []) if item['attributes']['identifier'] == identifier]
    if len(matches) > 1:
        raise RuntimeError('Ambiguous bundle identifier')
    return matches[0] if matches else None


def main():
    receipt = {'operationId': '20261030-moment-successor-identifiers-v2',
               'scriptSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               'team': TEAM, 'identifiers': [], 'status': 'running'}
    RECEIPT.parent.mkdir(parents=True, exist_ok=True)
    def save():
        receipt['updatedAtUtc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        temporary = RECEIPT.with_suffix('.tmp')
        temporary.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
        temporary.replace(RECEIPT)
    save()
    for identifier, (name, required) in TARGETS.items():
        bundle = find_bundle(identifier)
        if bundle is None:
            try:
                api('bundleIds', 'POST', {'data': {'type': 'bundleIds', 'attributes': {
                    'identifier': identifier, 'name': name, 'platform': 'IOS'}}})
            except Exception:
                # A lost response must be reconciled, never blindly replayed.
                if find_bundle(identifier) is None:
                    raise
            bundle = find_bundle(identifier)
            if bundle is None:
                raise RuntimeError('Created bundle not visible on independent readback')
        row = {'identifier': identifier, 'resourceId': bundle['id'], 'capabilities': []}
        receipt['identifiers'].append(row); save()
        for capability in required:
            def capabilities():
                return api('bundleIds/' + bundle['id'] + '/bundleIdCapabilities')['data']
            existing = capabilities()
            if not any(x['attributes']['capabilityType'] == capability for x in existing):
                try:
                    api('bundleIdCapabilities', 'POST', {'data': {'type': 'bundleIdCapabilities',
                        'attributes': {'capabilityType': capability},
                        'relationships': {'bundleId': {'data': {'type': 'bundleIds', 'id': bundle['id']}}}}})
                except Exception:
                    if not any(x['attributes']['capabilityType'] == capability for x in capabilities()):
                        raise
            if not any(x['attributes']['capabilityType'] == capability for x in capabilities()):
                raise RuntimeError('Capability readback mismatch')
            row['capabilities'].append(capability); save()
        print(json.dumps(row))
    receipt['status'] = 'identifiers_registered'
    receipt['remaining'] = ['App Store Connect application record', 'App Group container association',
                            'matching App Store profiles', 'internal and external beta groups',
                            'Atlas application binding within the existing project']
    save()


if __name__ == '__main__':
    main()
