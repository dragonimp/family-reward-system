#!/usr/bin/env python3
"""Prepare a committed release flavor in the build workspace, never in the checkout."""
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

source, options_path, manifest_path = map(Path, sys.argv[1:4])
flavor = sys.argv[4]
if flavor != 'successor':
    raise SystemExit('Moment releases must use the new application identity; old-ID updates are disabled')
team = 'JQPH54K7SD'
base = 'net.impx.happylife'
pbx = (source / 'parent-app/ios/HappyLifeParent.xcodeproj/project.pbxproj').read_text()
versions = set(re.findall(r'MARKETING_VERSION = ([^;]+);', pbx))
builds = set(re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);', pbx))
assert len(versions) == len(builds) == 1
version, build = next(iter(versions)), next(iter(builds))
assert re.fullmatch(r'[0-9]+(\.[0-9]+){1,2}', version)
assert re.fullmatch(r'[0-9]+(\.[0-9]+)*', build)
options = plistlib.loads((source / 'parent-app/ios/ExportOptions.example.plist').read_bytes())
options['teamID'] = team
automatic = os.environ.get('MOMENT_IOS_AUTOMATIC_SIGNING') == '1'
if automatic:
    # Explicit bootstrap only: Xcode contacts Apple with the existing team API identity.
    # Bundle ID, entitlements and IPA verification remain unchanged.
    options['signingStyle'] = 'automatic'
    options.pop('provisioningProfiles', None)
else:
    profile_root = Path.home() / '.local/share/apple-signing' / team
    profiles = []
    for file in profile_root.glob('*.mobileprovision'):
        result = subprocess.run(['security', 'cms', '-D', '-i', str(file)], capture_output=True)
        if result.returncode:
            continue
        profile = plistlib.loads(result.stdout)
        entitlements = profile.get('Entitlements', {})
        if (profile.get('TeamIdentifier') != [team] or profile.get('ProvisionedDevices')
                or profile.get('ProvisionsAllDevices') or entitlements.get('get-task-allow')
                or profile['ExpirationDate'].replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc)):
            continue
        profiles.append(profile)
    for bundle in options['provisioningProfiles']:
        assert bundle in (base, base + '.watchkitapp', base + '.share')
        candidates = [p for p in profiles if p['Entitlements'].get('application-identifier') == team + '.' + bundle]
        if bundle in (base, base + '.share'):
            candidates = [p for p in candidates if 'group.' + base in p['Entitlements'].get('com.apple.security.application-groups', [])]
        if bundle == base:
            candidates = [p for p in candidates if p['Entitlements'].get('aps-environment') == 'production']
        if not candidates:
            raise SystemExit(f'No valid App Store profile for {bundle}')
        selected = max(candidates, key=lambda p: p.get('CreationDate', datetime.datetime.min))
        options['provisioningProfiles'][bundle] = selected['UUID']
options_path.write_bytes(plistlib.dumps(options))
manifest = {'flavor': flavor, 'bundleId': base, 'appGroup': 'group.' + base,
            'version': version, 'build': build, 'team': team, 'automaticSigning': automatic}
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Version/profile preflight: {version} ({build}), {flavor}, {base}')
