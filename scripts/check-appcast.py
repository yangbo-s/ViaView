#!/usr/bin/env python3
"""Verify feed metadata and archive signature against the shipped public key."""
import base64
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

feed, archive, plist = map(Path, sys.argv[1:])
info = plistlib.loads(plist.read_bytes())
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(feed).findall('./channel/item')
assert len(items) == 1, 'Expected one release in the feed'
item = items[0]
assert item.findtext(f'{ns}version') == info['CFBundleVersion'], 'Build mismatch'
assert item.findtext(f'{ns}shortVersionString') == info['CFBundleShortVersionString'], 'Version mismatch'
assert item.findtext(f'{ns}minimumSystemVersion') == info['LSMinimumSystemVersion'], 'Minimum OS mismatch'
enclosure = item.find('enclosure')
assert enclosure is not None, 'Missing archive enclosure'
expected_url = f"https://github.com/yangbo-s/ViaView/releases/download/v{info['CFBundleShortVersionString']}/{archive.name}"
assert enclosure.get('url') == expected_url, 'Download URL mismatch'
assert int(enclosure.get('length', '0')) == archive.stat().st_size, 'Archive length mismatch'
signature = base64.b64decode(enclosure.attrib[f'{ns}edSignature'], validate=True)
public_key = base64.b64decode(info['SUPublicEDKey'], validate=True)
assert len(signature) == 64 and len(public_key) == 32, 'Invalid Ed25519 signature/key size'
# CryptoKit independently verifies the archive, using only the app's public key.
with tempfile.TemporaryDirectory(prefix='viaview-signature-') as temporary:
    script = Path(temporary) / 'verify.swift'
    script.write_text('''import Foundation
import CryptoKit
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: CommandLine.arguments[1])!)
let signature = Data(base64Encoded: CommandLine.arguments[2])!
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
guard key.isValidSignature(signature, for: data) else { exit(1) }
''')
    subprocess.run(['xcrun', 'swift', '-module-cache-path', str(Path(temporary) / 'cache'), str(script),
                    info['SUPublicEDKey'], enclosure.attrib[f'{ns}edSignature'], str(archive)], check=True)
print('PASS appcast version, build, minimum OS, URL, size and Ed25519 archive signature')
