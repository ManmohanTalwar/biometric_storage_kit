#!/usr/bin/env python3
"""Correct DN 1.4.0 community pod metadata without changing native payloads.

Run after `dn plugin build`. This command does not publish or modify the SDK.
The reviewed archive must be the exact archive uploaded; the ordinary
`dn plugin publish` rebuild would regenerate the incorrect metadata.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def contents(path):
    files = {}
    with tarfile.open(path) as archive:
        for member in archive.getmembers():
            name = PurePosixPath(member.name)
            if name.is_absolute() or '..' in name.parts or '\\' in member.name:
                raise ValueError('Unsafe archive path')
            if not member.isdir() and not member.isfile():
                raise ValueError('Links and special files are not release inputs')
            if member.isfile():
                if member.name in files:
                    raise ValueError('Duplicate archive member')
                files[member.name] = archive.extractfile(member).read()
    return files


def normalize(binary, source, output, expected_owner, name, version):
    before = contents(binary)
    source_files = contents(source)
    root = f'{name}-{version}'
    manifest_path = f'{root}/manifest.json'
    manifest = json.loads(before[manifest_path])
    if (manifest['name'], manifest['version'], manifest['owner']) != (name, version, expected_owner):
        raise ValueError('Artifact identity mismatch')
    if manifest['pubspec']['publish_to'] != 'https://dartpub.dev':
        raise ValueError('Package is not configured for dartpub.dev')
    if manifest['pubspec']['repository'] != f'https://github.com/{expected_owner}/{name}':
        raise ValueError('Repository identity mismatch')
    if b'Apache License' not in before[f'{root}/LICENSE']:
        raise ValueError('Expected full Apache licence')
    podspec_path = f'{root}/{name}.podspec'
    old_spec = before[podspec_path].decode()
    expected_licence = "s.license          = { :type => 'Commercial' }"
    expected_author = "s.author           = { 'DartNative' => 'hello@dartnative.com' }"
    if old_spec.count(expected_licence) != 1 or old_spec.count(expected_author) != 1:
        raise ValueError('SDK metadata template changed; review before normalizing')
    new_spec = old_spec.replace(expected_licence, "s.license          = { :type => 'Apache-2.0' }").replace(
        expected_author, f"s.author           = '{name} contributors'")
    after = dict(before)
    after[podspec_path] = new_spec.encode()
    # Package-owned metadata extension, not an official SDK schema field.
    declared = set(manifest['platforms']['android']['maven_dependencies'])
    licenses = {}
    for group, artifact, dependency_version in [
        ('androidx.annotation', 'annotation', '1.7.1'),
        ('androidx.biometric', 'biometric', '1.1.0'),
    ]:
        coordinate = f'{group}:{artifact}:{dependency_version}'
        if coordinate not in declared:
            raise ValueError('Expected dependency declaration changed; review licences')
        licenses[coordinate] = {
            'spdx': 'Apache-2.0', 'bundled': False,
            'pom': 'https://dl.google.com/dl/android/maven2/'
                   + group.replace('.', '/') + f'/{artifact}/{dependency_version}/'
                   + f'{artifact}-{dependency_version}.pom',
        }
    manifest['third_party_licenses'] = licenses
    after[manifest_path] = (json.dumps(manifest, indent=2) + '\n').encode()
    # The iOS publishing host already requires macOS/Ruby for CocoaPods.
    # Use a real safe YAML parser rather than partially interpreting pubspec.
    parsed = subprocess.run(
        ['ruby', '-rjson', '-ryaml', '-e',
         'puts JSON.generate(YAML.safe_load(STDIN.read, permitted_classes: [], aliases: false))'],
        input=source_files.get('pubspec.yaml', b''), capture_output=True, check=True,
    )
    if json.loads(parsed.stdout) != manifest['pubspec']:
        raise ValueError('Source pubspec differs from binary manifest')
    binary_dart = {n[len(root) + 1:]: data for n, data in before.items()
                   if n.startswith(f'{root}/lib/')}
    source_dart = {n: data for n, data in source_files.items() if n.startswith('lib/')}
    if not binary_dart or source_dart != binary_dart:
        raise ValueError('Source and binary Dart bindings differ')
    if source_files.get('LICENSE') != before[f'{root}/LICENSE']:
        raise ValueError('Source and binary licences differ')
    if source_files.get('NOTICES') != before[f'{root}/NOTICES']:
        raise ValueError('Source and binary notices differ')
    native_hashes = {n: sha(b) for n, b in before.items() if n.startswith((f'{root}/ios/', f'{root}/android/'))}
    if not native_hashes:
        raise ValueError('Expected native payloads')
    for n, h in native_hashes.items():
        if sha(after[n]) != h:
            raise ValueError('Unexpected native payload change')
    if output.exists():
        raise FileExistsError('Refusing to overwrite an already reviewed archive')
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('xb') as raw:
        with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as gz:
            with tarfile.open(fileobj=gz, mode='w', format=tarfile.PAX_FORMAT) as archive:
                for n, data in sorted(after.items()):
                    info = tarfile.TarInfo(n)
                    info.size = len(data)
                    info.mode = 0o644
                    archive.addfile(info, io.BytesIO(data))
    verified = contents(output)
    if verified != after:
        raise ValueError('Archive roundtrip changed payloads')
    receipt = {
        'package': name, 'version': version, 'owner': expected_owner,
        'input_sha256': sha(binary.read_bytes()),
        'reviewed_sha256': sha(output.read_bytes()),
        'source_archive_sha256': sha(source.read_bytes()),
        'changed_members': [podspec_path, manifest_path],
        'correction': 'Apache-2.0 licence, contributor attribution and additive direct-dependency licence metadata; DN 1.4.0 generated metadata workaround',
        'native_payloads_unchanged': native_hashes,
        'published': False,
    }
    output.with_suffix(output.suffix + '.receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({k: receipt[k] for k in ('package', 'version', 'reviewed_sha256', 'changed_members')}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True, type=Path)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--owner', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    pubspec = (root / 'pubspec.yaml').read_text()
    name = re.search(r'^name:\s*(\S+)\s*$', pubspec, re.M).group(1)
    version = re.search(r'^version:\s*(\S+)\s*$', pubspec, re.M).group(1)
    normalize(args.binary, args.source, args.output, args.owner, name, version)


if __name__ == '__main__':
    main()
