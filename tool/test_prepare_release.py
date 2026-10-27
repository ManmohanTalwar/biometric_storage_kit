import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

from prepare_release import contents, normalize


class ReleaseMetadataTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.name = 'biometric_storage_kit'
        self.version = '0.1.0-dev.1'
        self.owner = 'ExamplePublisher'
        self.root = f'{self.name}-{self.version}'
        self.binary = self.directory / 'binary.tar.gz'
        self.source = self.directory / 'source.tar.gz'
        self.output = self.directory / 'reviewed.tar.gz'
        self.manifest = {'name': self.name, 'version': self.version, 'owner': self.owner,
                         'platforms': {'android': {'maven_dependencies': ['androidx.annotation:annotation:1.7.1', 'androidx.biometric:biometric:1.1.0']}},
                         'pubspec': {'publish_to': 'https://dartpub.dev',
                                     'repository': f'https://github.com/{self.owner}/{self.name}'}}
        self.members = {
            f'{self.root}/manifest.json': json.dumps(self.manifest).encode(),
            f'{self.root}/LICENSE': b'Apache License test fixture',
            f'{self.root}/NOTICES': b'Synthetic attribution',
            f'{self.root}/{self.name}.podspec': (
                "s.license          = { :type => 'Commercial' }\n"
                "s.author           = { 'DartNative' => 'hello@dartnative.com' }\n"
                "s.user_target_xcconfig = { 'DEAD_CODE_STRIPPING' => 'NO' }\n"
            ).encode(),
            f'{self.root}/lib/fixture.dart': b'// Synthetic Dart binding',
            f'{self.root}/ios/library.a': b'untouched iOS native bytes',
            f'{self.root}/android/plugin.aar': b'untouched Android native bytes',
        }
        self.write(self.binary, self.members)
        self.source_members = {'LICENSE': b'Apache License test fixture', 'NOTICES': b'Synthetic attribution',
                               'pubspec.yaml': json.dumps(self.manifest['pubspec']).encode(),
                               'lib/fixture.dart': b'// Synthetic Dart binding'}
        self.write(self.source, self.source_members)

    def write(self, path, entries):
        with tarfile.open(path, 'w:gz') as archive:
            for name, data in entries.items():
                info = tarfile.TarInfo(name)
                info.size = len(data)
                archive.addfile(info, io.BytesIO(data))

    def prepare(self):
        normalize(self.binary, self.source, self.output, self.owner, self.name, self.version)

    def test_only_license_and_author_change_native_and_linker_settings_survive(self):
        self.prepare()
        after = contents(self.output)
        pod = f'{self.root}/{self.name}.podspec'
        self.assertEqual(set(p for p in after if after[p] != self.members[p]), {pod, f'{self.root}/manifest.json'})
        manifest = json.loads(after[f'{self.root}/manifest.json'])
        for key, value in self.manifest.items():
            self.assertEqual(manifest[key], value)
        self.assertEqual(len(manifest['third_party_licenses']), 2)
        self.assertIn(b"'Apache-2.0'", after[pod])
        self.assertNotIn(b'Commercial', after[pod])
        self.assertIn(b"'DEAD_CODE_STRIPPING' => 'NO'", after[pod])
        self.assertEqual(contents(self.binary), self.members)

    def test_refuses_unknown_builder_template(self):
        self.members[f'{self.root}/{self.name}.podspec'] = b'changed upstream template'
        self.write(self.binary, self.members)
        with self.assertRaisesRegex(ValueError, 'template changed'):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_refuses_owner_mismatch(self):
        with self.assertRaisesRegex(ValueError, 'identity mismatch'):
            normalize(self.binary, self.source, self.output, 'SomeoneElse', self.name, self.version)
        self.assertFalse(self.output.exists())

    def test_refuses_mismatching_source_licence(self):
        self.source_members['LICENSE'] = b'different'
        self.write(self.source, self.source_members)
        with self.assertRaisesRegex(ValueError, 'licences differ'):
            self.prepare()

    def test_refuses_different_source_pubspec(self):
        changed = dict(self.manifest['pubspec'], version='99.0.0', name='unrelated')
        self.source_members['pubspec.yaml'] = json.dumps(changed).encode()
        self.write(self.source, self.source_members)
        with self.assertRaisesRegex(ValueError, 'pubspec differs'):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_refuses_missing_or_changed_dart_bindings(self):
        for changed in (None, b'changed API'):
            with self.subTest(changed=changed):
                self.source_members.pop('lib/fixture.dart', None)
                if changed is not None:
                    self.source_members['lib/fixture.dart'] = changed
                self.write(self.source, self.source_members)
                with self.assertRaisesRegex(ValueError, 'Dart bindings differ'):
                    self.prepare()
                self.assertFalse(self.output.exists())

    def test_refuses_symbolic_links(self):
        with tarfile.open(self.binary, 'w:gz') as archive:
            entry = tarfile.TarInfo('linked')
            entry.type = tarfile.SYMTYPE
            entry.linkname = '../outside'
            archive.addfile(entry)
        with self.assertRaisesRegex(ValueError, 'Links and special files'):
            contents(self.binary)


if __name__ == '__main__':
    unittest.main()
