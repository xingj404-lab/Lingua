#!/usr/bin/env python3
from pathlib import Path
import plistlib, json, subprocess
root = Path(__file__).resolve().parent.parent
p = root / 'Distribution'
(p / 'Resources').mkdir(parents=True, exist_ok=True)
info = {'CFBundleExecutable':'$(EXECUTABLE_NAME)', 'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleName':'Lingua', 'CFBundleDisplayName':'Lingua', 'CFBundlePackageType':'APPL', 'CFBundleShortVersionString':'$(MARKETING_VERSION)', 'CFBundleVersion':'$(CURRENT_PROJECT_VERSION)', 'LSMinimumSystemVersion':'$(MACOSX_DEPLOYMENT_TARGET)', 'CFBundleLocalizations':['zh-Hans','en','ja','ko'], 'CFBundleDevelopmentRegion':'en', 'NSHighResolutionCapable':True, 'NSPrincipalClass':'NSApplication', 'NSHumanReadableCopyright':'Copyright © 2026 Lingua.', 'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True}, 'ITSAppUsesNonExemptEncryption':False}
info['LSApplicationCategoryType'] = 'public.app-category.productivity'
(p/'Info.plist').write_bytes(plistlib.dumps(info))
(p/'Lingua.entitlements').write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True, 'com.apple.security.network.client':True, 'com.apple.security.files.user-selected.read-write':True}))
manifest = {'NSPrivacyTracking':False, 'NSPrivacyTrackingDomains':[], 'NSPrivacyCollectedDataTypes':[], 'NSPrivacyAccessedAPITypes':[{'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategory'+category, 'NSPrivacyAccessedAPITypeReasons':reasons} for category,reasons in [('UserDefaults',['CA92.1']), ('SystemBootTime',['35F9.1']), ('FileTimestamp',['C617.1','3B52.1'])]]}
(p/'Resources/PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps(manifest))
icons = p/'Resources/Assets.xcassets/AppIcon.appiconset'; icons.mkdir(parents=True,exist_ok=True)
items = []
for size in [16,32,128,256,512]:
    for scale in [1,2]:
        name = f'icon_{size}@{scale}x.png'
        subprocess.run(['sips','-z',str(size*scale),str(size*scale),str(root/'Sources/LinguaMac/Resources/AppIcon.png'),'--out',str(icons/name)], stdout=subprocess.DEVNULL,check=True)
        items.append({'idiom':'mac','size':f'{size}x{size}','scale':f'{scale}x','filename':name})
(icons/'Contents.json').write_text(json.dumps({'images':items,'info':{'author':'xcode','version':1}},indent=2))
