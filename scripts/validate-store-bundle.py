#!/usr/bin/env python3
"""Offline packaging checks. Does not replace Xcode's App Store validation."""
import json, plistlib, subprocess, sys
from pathlib import Path
app = Path(sys.argv[1])
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'app.lingua.mac'
assert info.get('LSApplicationCategoryType') == 'public.app-category.productivity', 'Missing or unexpected App Store application category'
resources = app/'Contents/Resources'
privacy = plistlib.loads((resources/'PrivacyInfo.xcprivacy').read_bytes())
assert privacy['NSPrivacyTracking'] is False
assert len(privacy['NSPrivacyAccessedAPITypes']) >= 3
for language in ['zh-Hans','en','ja','ko']:
    assert (resources/f'Legal/privacy-{language}.md').is_file()
assert len(list((resources/'Legal/ThirdParty').glob('*/LICENSE*'))) >= 10
manifests = list((resources/'BundledModels').glob('*/.lingua-manifest.json'))
assert len(manifests) == 1
model = json.loads(manifests[0].read_text()); folder = manifests[0].parent/model['revision']
assert model['repository'] == 'mlx-community/Hy-MT2-1.8B-4bit'
for entry in model['entries']:
    assert (folder/entry['path']).stat().st_size == entry.get('lfs',{}).get('size',entry.get('size'))
assert list(resources.rglob('*.metallib')), 'Missing Metal library'
assert (app/'Contents/Frameworks/TranslationCore.framework').exists()
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
result = subprocess.run(['codesign','-d','--entitlements',':-',str(app)],capture_output=True,check=True)
entitlements = plistlib.loads(result.stdout)
assert entitlements['com.apple.security.app-sandbox'] is True
assert entitlements['com.apple.security.network.client'] is True
assert entitlements['com.apple.security.files.user-selected.read-write'] is True
assert not entitlements.get('com.apple.security.cs.disable-library-validation',False)
assert not entitlements.get('com.apple.security.cs.allow-unsigned-executable-memory',False)
print('PASS: category, signature, sandbox, privacy, localizations, licenses, native framework, Metal and bundled model')
