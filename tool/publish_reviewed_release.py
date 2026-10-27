#!/usr/bin/env python3
"""DN 1.4.0 workaround: upload a reviewed archive without rebuilding it.

Defaults to a local dry run. --publish explicitly uploads to dartpub.dev using
DN_PUBLISH_TOKEN. The SDK's installed multipart protocol is not a documented
public upload API; review it again when upgrading the SDK. Never log tokens.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import re
import urllib.error
import urllib.request

from prepare_release import contents, sha

API = 'https://dartpub.dev'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def prepare(binary, source, root):
    receipt = json.loads(binary.with_suffix(binary.suffix + '.receipt.json').read_text())
    if sha(binary.read_bytes()) != receipt['reviewed_sha256']:
        raise ValueError('Reviewed binary checksum mismatch')
    if sha(source.read_bytes()) != receipt['source_archive_sha256']:
        raise ValueError('Reviewed source checksum mismatch')
    name, version, owner = (receipt[k] for k in ('package', 'version', 'owner'))
    files, sources = contents(binary), contents(source)
    manifest_text = files[f'{name}-{version}/manifest.json'].decode()
    manifest = json.loads(manifest_text)
    if (manifest['name'], manifest['version'], manifest['owner']) != (name, version, owner):
        raise ValueError('Reviewed identity mismatch')
    if sources['pubspec.yaml'] != (root / 'pubspec.yaml').read_bytes():
        raise ValueError('Repository pubspec changed since artifact review')
    if sources['README.md'] != (root / 'README.md').read_bytes():
        raise ValueError('Repository README changed since artifact review')
    readme = sources['README.md'].decode()
    examples = (root / 'example/README.md').read_text()
    for path in sorted((root / 'example/lib').rglob('*.dart')):
        examples += f'\n\n## {path.relative_to(root)}\n\n```dart\n{path.read_text()}\n```\n'
    changelog = sources['CHANGELOG.md'].decode()
    section = re.search(r'^## ' + re.escape(version) + r'\s*\n(.*?)(?=^## |\Z)', changelog, re.M | re.S)
    if section is None:
        raise ValueError('Missing version changelog')
    fields = {'owner': owner, 'name': name, 'version': version,
              'sha256': receipt['reviewed_sha256'], 'readme': readme,
              'examples': examples, 'changelog': section.group(1).strip(),
              'manifest': manifest_text, 'source_b64': base64.b64encode(source.read_bytes()).decode()}
    return fields, receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    fields, receipt = prepare(args.binary, args.source, root)
    print(json.dumps({k: fields[k] for k in ('owner', 'name', 'version', 'sha256')}))
    if not args.publish:
        print('Dry run only. No network request or upload performed.')
        return
    token = os.environ.get('DN_PUBLISH_TOKEN')
    if not token:
        raise ValueError('DN_PUBLISH_TOKEN is required; do not put credentials in arguments')
    opener = urllib.request.build_opener(NoRedirect)
    check_url = API + '/api/plugins/check-name?owner=' + fields['owner'] + '&name=' + fields['name']
    try:
        response = opener.open(check_url, timeout=30)
        response.close()
        raise ValueError('Plugin must be registered before publishing')
    except urllib.error.HTTPError as error:
        body = json.loads(error.read())
        if error.code != 409 or body.get('code') != 'taken':
            raise ValueError('Registry did not confirm a registered name') from None
    boundary = 'dn-reviewed-' + secrets.token_hex(24)
    chunks = []
    for key, value in fields.items():
        chunks += [f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n'.encode(),
                   value.encode(), b'\r\n']
    filename = fields['name'] + '-' + fields['version'] + '.tar.gz'
    chunks += [f'--{boundary}\r\nContent-Disposition: form-data; name="tarball"; filename="{filename}"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode(),
               args.binary.read_bytes(), f'\r\n--{boundary}--\r\n'.encode()]
    request = urllib.request.Request(API + '/api/plugins/publish', data=b''.join(chunks),
        headers={'Authorization': 'Bearer ' + token, 'Origin': API,
                 'Content-Type': 'multipart/form-data; boundary=' + boundary}, method='POST')
    try:
        with opener.open(request, timeout=120) as response:
            status, result = response.status, json.load(response)
    except urllib.error.HTTPError as error:
        # Do not print request headers or arbitrary response bodies.
        raise RuntimeError(f'Publish HTTP {error.code}; inspect registry status before retrying') from None
    if status != 200 or not isinstance(result.get('version'), dict):
        raise RuntimeError('Publish response did not satisfy the SDK contract')
    response_path = args.binary.with_suffix(args.binary.suffix + '.publish.json')
    response_path.write_text(json.dumps(result, indent=2) + '\n')
    print('Registry accepted a version response. Verify public downloads before declaring completion.')


if __name__ == '__main__':
    main()
