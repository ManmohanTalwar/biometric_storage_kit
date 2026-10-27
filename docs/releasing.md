# Publishing with DartNative 1.4.0

Version 0.1.0 is an initial release with explicitly limited device qualification;
see [validation](../VALIDATION.md). Publishing does not authorize real-user migration.

The installed standalone builder generates a consumer podspec with a hardcoded
Commercial licence and DartNative author, despite this package's Apache-2.0
source podspec. The ordinary `dn plugin publish` rebuilds immediately before
uploading, so pre-editing its output would not preserve a correction. The SDK is
left unchanged.

This package's reproducible workaround uses the official builder, then
`tool/prepare_release.py` to correct only generated podspec attribution/licence
and add declared external Maven licence metadata to the manifest. It requires
Python 3 and Ruby/Psych (available on the macOS iOS publishing host). It rejects
unsafe archive members, mismatched identity, differing source pubspec/Dart
bindings and differing notices. Every native payload stays byte-identical to
the official build. Its receipt hashes the exact reviewed binary and source.

```sh
dn plugin build --owner ManmohanTalwar --out /tmp/biometric-release
python3 -m unittest discover -s tool -p test_prepare_release.py
python3 tool/prepare_release.py \
  --binary /tmp/biometric-release/biometric_storage_kit-0.1.0.tar.gz \
  --source /tmp/biometric-release/biometric_storage_kit-0.1.0-source.tar.gz \
  --output /tmp/biometric-release/biometric_storage_kit-0.1.0-reviewed.tar.gz \
  --owner ManmohanTalwar
python3 tool/check_distribution.py \
  /tmp/biometric-release/biometric_storage_kit-0.1.0-reviewed.tar.gz \
  /tmp/biometric-release/biometric_storage_kit-0.1.0-source.tar.gz
```

After independent review and the authorized GitHub push/website registration,
`tool/publish_reviewed_release.py` dry-runs by default with the same `--binary`
and `--source` paths. Only an explicit `--publish` uploads. Supply the authorized
publisher credential through `DN_PUBLISH_TOKEN`, never a command argument or
committed file. It sends the exact reviewed archive and its normalized manifest,
source archive, README, example and changelog using the installed CLI's multipart
protocol at dartpub.dev. This is a source-backed compatibility workaround, **not
a documented public upload API**. It rejects redirects and requires the same
HTTP 200 plus version-map response contract as the CLI. Never blindly retry an
ambiguous upload or overwrite a version.

Recheck this workaround against any new SDK; do not carry it forward implicitly.
Normal `dn plugin sync` is appropriate for later README/example-only updates and
does not rebuild native binaries. Public version/source/native downloads must be
verified separately, followed by a clean hosted dependency resolution and
consumer builds. Record outcomes and checksums in the release receipt. The Pub
source archive contains Dart bindings; complete native source, tests and media
remain in the public GitHub repository.
