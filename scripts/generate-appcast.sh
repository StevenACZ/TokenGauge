#!/bin/bash
set -euo pipefail
cd -P "$(dirname "$0")/.."
app="${TOKENGAUGE_APP_PATH:-$PWD/dist/distribution/TokenGauge.app}"
output_dir="${TOKENGAUGE_ARTIFACTS_DIR:-$PWD/dist/release-artifacts}"
signer="${TOKENGAUGE_SPARKLE_BIN:-$PWD/.build/artifacts/sparkle/Sparkle/bin}/sign_update"
[[ -x "$signer" ]] || { echo 'Sparkle sign_update is missing.' >&2; exit 69; }
scripts/verify-release.sh "$app"
scripts/verify-update-key.sh "$app/Contents/Info.plist"
mkdir -p "$output_dir"
workspace="$(mktemp -d "$output_dir/.appcast.XXXXXX")"
trap 'rm -rf "$workspace"' EXIT
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
zip_name="TokenGauge-$version.zip"
[[ ! -e "$output_dir/$zip_name" && ! -e "$output_dir/appcast.xml" ]] || exit 73
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent "$app" "$workspace/$zip_name"
scripts/verify-release.sh "$workspace/$zip_name"
"$signer" "$workspace/$zip_name" > "$workspace/signature"
python3 - "$app/Contents/Info.plist" "$workspace" "$zip_name" <<'PY'
import email.utils
import pathlib
import plistlib
import sys
import xml.etree.ElementTree as ET
plist_path, directory, zip_name = sys.argv[1:]
directory = pathlib.Path(directory)
with open(plist_path, 'rb') as stream:
    info = plistlib.load(stream)
attributes = ET.fromstring('<enclosure xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" ' + (directory / 'signature').read_text().strip() + '/>').attrib
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
if not attributes.get(f'{{{ns}}}edSignature') or int(attributes['length']) != (directory / zip_name).stat().st_size:
    raise SystemExit('Invalid Sparkle signature metadata')
ET.register_namespace('sparkle', ns)
version = info['CFBundleShortVersionString']
repo = 'https://github.com/StevenACZ/TokenGauge'
rss = ET.Element('rss', version='2.0')
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = 'TokenGauge'
item = ET.SubElement(channel, 'item')
for tag, value in [('title', version), ('link', f'{repo}/releases/tag/v{version}'), (f'{{{ns}}}version', info['CFBundleVersion']), (f'{{{ns}}}shortVersionString', version), (f'{{{ns}}}minimumSystemVersion', info['LSMinimumSystemVersion']), ('pubDate', email.utils.formatdate(usegmt=True))]:
    ET.SubElement(item, tag).text = value
ET.SubElement(item, 'enclosure', url=f'{repo}/releases/download/v{version}/{zip_name}', type='application/octet-stream', **attributes)
ET.indent(rss, space='  ')
ET.ElementTree(rss).write(directory / 'appcast.xml', encoding='utf-8', xml_declaration=True)
PY
"$signer" "$workspace/appcast.xml"
"$signer" --verify "$workspace/appcast.xml"
python3 - "$signer" "$workspace/$zip_name" "$workspace/appcast.xml" <<'PYVERIFY'
import subprocess
import sys
import xml.etree.ElementTree as ET
signature = ET.parse(sys.argv[3]).find('.//enclosure').get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature')
subprocess.run([sys.argv[1], '--verify', sys.argv[2], signature], check=True)
PYVERIFY
mv "$workspace/$zip_name" "$output_dir/$zip_name"
mv "$workspace/appcast.xml" "$output_dir/appcast.xml"
echo "Update artifacts: $output_dir"
