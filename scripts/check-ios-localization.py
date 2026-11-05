#!/usr/bin/env python3
"""Check versioned catalogs, platform generation, and real Swift compiler key coverage."""
import argparse, importlib.util, json, re, os
from pathlib import Path
import sys
sys.dont_write_bytecode = True
from swift_strings import tokens
ROOT=Path(__file__).resolve().parents[1]
SDK=Path(os.environ.get('AGENT_IDENTITY_ROOT', ROOT.parent/'AgentIdentity'))
if not (SDK/'localization/generate.py').is_file(): SDK=Path.home()/'Projects/AgentIdentity'
spec=importlib.util.spec_from_file_location('language_generator',SDK/'localization/generate.py');generator=importlib.util.module_from_spec(spec);spec.loader.exec_module(generator)
TABLES=[('parent-app/ios/HappyLifeParent','happylifeparent'),('parent-app/ios/HappyLifeShare','happylifeshare'),('watch-app/apple/HappyLifeWatch','happylifewatch')]
FORMAT=re.compile(r'%(?:\d+\$)?[-+0 #]*(?:@|lld|llu|ld|d|(?:\.[0-9]+)?[fge])')
p=argparse.ArgumentParser();p.add_argument('--extracted',type=Path);p.add_argument('--report',type=Path);args=p.parse_args()
# These raw exercise kinds are persisted and sent to the server; translated labels are separate.
ALLOWED_RAW={'ExerciseView.swift': {'慢跑','散步','自由运动'}, 'DiningModels.swift': {'川', '湘', '辣', '火锅'}}
for folder,_ in TABLES:
 for path in (ROOT/folder).glob('*.swift'):
  source=path.read_text()
  for start,end,value in tokens(source):
   if not re.search('[\u3400-\u9fff]',value): continue
   if re.search(r'String\(localized:\s*$',source[max(0,start-30):start]): continue
   assert value in ALLOWED_RAW.get(path.name,set()),f'Unlocalized Swift string in {path.name}: {value}'
  for number,line in enumerate(source.splitlines(),1):
   if 'String(localized:' in line:
    assert 'bundle: AgentIdentityLanguage.appBundle(' in line,f'Explicit app bundle required: {path.name}:{number}'
main=generator.read_catalog(ROOT/'localization/linko-moment.v1.json')
keys={v.get('iosKey',k) for k,v in main['messages'].items()}
for folder,name in TABLES:
 for table,catalog in [('Localizable',main),('InfoPlist',generator.read_catalog(ROOT/f'localization/linko-moment-{name}-info.v1.json'))]:
  for key,value in catalog['messages'].items():
   assert sorted(FORMAT.findall(value['zh-Hans']))==sorted(FORMAT.findall(value['en'])),f'Format mismatch: {key}'
   assert not re.search('[\u3400-\u9fff]',value['en']),f'Untranslated English: {key}'
  for locale in generator.LOCALES:
   path=ROOT/folder/f'{locale}.lproj/{table}.strings'
   assert path.read_text()==generator.render(catalog,locale,'ios'),f'Stale resource: {path}'
checked=set()
missing=set()
if args.extracted:
 files=[p for p in args.extracted.rglob('*.stringsdata') if '/AgentIdentity' not in str(p) and 'GeneratedAsset' not in p.name]
 assert files,'No Swift compiler localization data found'
 for path in files:
  for table,entries in json.loads(path.read_text()).get('tables',{}).items():
   if table!='Localizable':continue
   for item in entries:
    if not item['key'].strip(): continue
    if item['key'] not in keys: missing.add(item['key'])
    checked.add(item['key'])
assert not missing, 'Missing translated compiler keys: '+json.dumps(sorted(missing),ensure_ascii=False)
report={'catalogKeys':len(keys),'compilerKeysChecked':len(checked),'supported':['zh-Hans','en'],'fallback':'en','targets':['iPhone/iPad','watchOS','Share extension']}
if args.report: args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
