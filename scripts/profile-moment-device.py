#!/usr/bin/env python3
"""Read-only iPhone Time Profiler capture; run in host-build-queue + host-build-output."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--seconds', type=int, default=30)
parser.add_argument('--label', required=True)
args = parser.parse_args()
assert 10 <= args.seconds <= 60
work = Path(os.environ['ATLAS_BUILD_WORK'])
out = Path(os.environ['ATLAS_BUILD_OUTPUT'])

def device_call(command, name):
    target = work / name
    subprocess.run(['xcrun', 'devicectl', *command, '--json-output', str(target)],
                   check=True, capture_output=True, text=True)
    return json.loads(target.read_text())['result']

devices = device_call(['list', 'devices'], 'devices.json')['devices']
connected = [d for d in devices if d.get('connectionProperties', {}).get('tunnelState') == 'connected']
assert len(connected) == 1, 'Exactly one connected test device required'
device = connected[0]
processes = device_call(['device', 'info', 'processes', '--device', device['identifier']], 'processes.json')
apps = [p for p in processes['runningProcesses'] if '/Linko%20Moment.app/' in p.get('executable', '')]
assert len(apps) == 1, 'Moment must be running on the test phone'
trace = work / 'capture.trace'
print('Recording ' + args.label + ' for ' + str(args.seconds) + ' seconds', flush=True)
subprocess.run(['xcrun', 'xctrace', 'record', '--device', device['deviceProperties']['name'],
                '--template', 'Time Profiler', '--attach', str(apps[0]['processIdentifier']),
                '--time-limit', str(args.seconds) + 's', '--output', str(trace)], check=True)
for schema in ['time-profile', 'potential-hangs']:
    subprocess.run(['xcrun', 'xctrace', 'export', '--input', str(trace), '--xpath',
                    '/trace-toc/run[@number="1"]/data/table[@schema="' + schema + '"]',
                    '--output', str(out / (schema + '.xml'))], check=True)
subprocess.run(['xcrun', 'xctrace', 'export', '--input', str(trace), '--toc', '--output', str(work / 'toc.xml')], check=True)
root = ET.parse(work / 'toc.xml').getroot()
summary = root.find('.//summary')
report = {'label': args.label, 'model': device['deviceProperties'].get('marketingName'),
          'durationSeconds': float(summary.findtext('duration')), 'start': summary.findtext('start-date'),
          'end': summary.findtext('end-date'), 'process': root.find('.//target/process').get('name'),
          'sampleRows': len(ET.parse(out / 'time-profile.xml').findall('.//row')),
          'potentialHangRows': len(ET.parse(out / 'potential-hangs.xml').findall('.//row'))}
(out / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report), flush=True)
