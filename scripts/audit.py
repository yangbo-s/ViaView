#!/usr/bin/env python3
"""Check the shipped resource and current repository contracts, without building."""
import hashlib
import base64
import json
import plistlib
import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
failures = []

def check(name, condition):
    print(f"{'PASS' if condition else 'FAIL'} {name}")
    if not condition:
        failures.append(name)

info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
entitlements = plistlib.loads((ROOT / 'Resources/Entitlements.plist').read_bytes())
package = (ROOT / 'Package.swift').read_text()
check('ViaView package, target and application names agree',
      all(info[key] == 'ViaView' for key in ('CFBundleName', 'CFBundleDisplayName', 'CFBundleExecutable'))
      and 'name: "ViaView"' in package and (ROOT / 'Sources/ViaView/Application/ViaViewApp.swift').is_file())
check('Existing application identity and sandbox remain compatible',
      info['CFBundleIdentifier'] == 'local.ChengTu' and entitlements.get('com.apple.security.app-sandbox') is True)
minimum = re.search(r'\.macOS\(\.v(\d+)\)', package)
check('Package and app deployment versions agree', minimum is not None
      and int(info['LSMinimumSystemVersion'].split('.')[0]) == int(minimum[1]))
check('Sparkle uses HTTPS, signed feeds and verification before extraction',
      info.get('SUFeedURL') == 'https://github.com/yangbo-s/ViaView/releases/latest/download/appcast.xml'
      and len(base64.b64decode(info.get('SUPublicEDKey', ''), validate=True)) == 32
      and info.get('SURequireSignedFeed') is True and info.get('SUVerifyUpdateBeforeExtraction') is True)
check('Sparkle sandbox installer and matching Mach service permissions are configured',
      info.get('SUEnableInstallerLauncherService') is True
      and entitlements.get('com.apple.security.temporary-exception.mach-lookup.global-name') ==
      [info['CFBundleIdentifier'] + '-spks', info['CFBundleIdentifier'] + '-spki'])
check('Update defaults check automatically, require install opt-in and disable profiling',
      info.get('SUEnableAutomaticChecks') is True and info.get('SUAutomaticallyUpdate') is False
      and info.get('SUEnableSystemProfiling') is False)
pins = json.loads((ROOT / 'Package.resolved').read_text())['pins']
check('Sparkle is pinned to the reviewed release',
      any(pin['identity'] == 'sparkle' and pin['state']['version'] == '2.10.0'
          and pin['state']['revision'] == 'eef1a539a373c1f1a320624b1130fc5de7b2e100' for pin in pins))

icons = ROOT / 'Sources/ViaView/Resources/Lucide'
manifest = json.loads((icons / 'source.json').read_text())['upstream_svg_sha256']
check('Every bundled icon matches its pinned upstream SHA-256',
      set(manifest) == {p.stem for p in icons.glob('*.svg')}
      and all(hashlib.sha256((icons / f'{name}.svg').read_bytes()).hexdigest() == digest
              for name, digest in manifest.items()))
icon_code = (ROOT / 'Sources/ViaView/UI/ToolbarIcons.swift').read_text().split('static let pointSize')[0]
used_icons = set()
for declaration in re.findall(r'^\s*case (.+)$', icon_code, re.MULTILINE):
    for item in declaration.split(','):
        parts = item.strip().split('=')
        used_icons.add(parts[-1].strip().strip('"'))
check('Toolbar icon declarations and packaged SVGs match', used_icons == set(manifest))
license_files = list(icons.glob('*LICENSE*'))
license_text = '\n'.join(path.read_text() for path in license_files)
check('Lucide and inherited Feather license text is retained',
      'ISC' in license_text and 'MIT' in license_text and 'Permission' in license_text)

obsolete = re.compile(r'\b(?:ChengTu|NativeViewer|ViewerSettings|toggleThumbnailSidebar|openPreview|copyColor)\b')
active_code = list((ROOT / 'Sources').rglob('*.swift')) + list((ROOT / 'scripts').rglob('*.swift')) + [ROOT / 'Package.swift']
check('Active Swift code has no obsolete product or action names',
      not any(obsolete.search(path.read_text()) for path in active_code))

current_docs = [ROOT / 'README.md', ROOT / 'CHANGELOG.md', ROOT / 'docs/ARCHITECTURE.md']
broken_links = []
for path in current_docs:
    for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', path.read_text()):
        target = unquote(target.strip('<>').split('#')[0])
        if not target or re.match(r'^[a-zA-Z]+:', target):
            continue
        if not (path.parent / target).exists():
            broken_links.append(f'{path.relative_to(ROOT)}: {target}')
check('Current documentation local links resolve', not broken_links)
for link in broken_links:
    print(f'  {link}')

def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from strings(child)
sidecar_path = ROOT / '.impeccable/design.json'
if sidecar_path.exists():
    sidecar = json.loads(sidecar_path.read_text())
    source_paths = [value for value in strings(sidecar) if value.startswith('Sources/')]
    check('Local design source references exist', bool(source_paths) and all((ROOT / path).exists() for path in source_paths))

print(f'\n{len(failures)} repository contract failure(s)')
sys.exit(bool(failures))
