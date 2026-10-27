import 'package:flutter/material.dart';
import 'package:biometric_storage/biometric_storage.dart';

const fixtureName = 'dn-upgrade.aGVsbG8_';
const textName = 'dn-upgrade-text';
const textValue = 'Synthetic migration record 2026';
const emptyName = 'dn-upgrade-empty';
const fixtureValue = 'Migration fixture • नमस्ते • 🔐\u0000end';

void main() => runApp(const MaterialApp(home: LegacyFixture()));

class LegacyFixture extends StatefulWidget {
  const LegacyFixture({super.key});
  @override
  State<LegacyFixture> createState() => _LegacyFixtureState();
}

class _LegacyFixtureState extends State<LegacyFixture> {
  var status = 'Ready: original biometric_storage 5.0.1';
  var busy = false;
  Future<BiometricStorageFile> store(String name) =>
      BiometricStorage().getStorage(
        name,
        options: StorageFileInitOptions(
          authenticationRequired: true,
          authenticationValidityDurationSeconds: -1,
          androidBiometricOnly: true,
          darwinBiometricOnly: true,
        ),
      );
  Future<void> run(String label, Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = 'Running $label';
    });
    try {
      await action();
      status = 'PASS: $label';
    } catch (e) {
      status = 'FAIL: $label (${e.runtimeType})';
    }
    // Only case name and outcome; never log a stored value.
    debugPrint('BIOQUAL $status');
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Legacy storage fixture')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(
            'Synthetic data only. Keep this app installed for the upgrade.',
          ),
          Text(status),
          ElevatedButton(
            onPressed: busy
                ? null
                : () => run('seed legacy', () async {
                    await (await store(fixtureName)).write(fixtureValue);
                    await (await store(emptyName)).write('');
                    await (await store(textName)).write(textValue);
                  }),
            child: const Text('1. Create legacy records'),
          ),
          ElevatedButton(
            onPressed: busy
                ? null
                : () => run('verify legacy', () async {
                    if (await (await store(fixtureName)).read() !=
                        fixtureValue) {
                      throw StateError('Unicode value mismatch');
                    }
                    if (await (await store(textName)).read() != textValue) {
                      throw StateError('Text value mismatch');
                    }
                    if (await (await store(emptyName)).read() != '') {
                      throw StateError('Empty value mismatch');
                    }
                  }),
            child: const Text('2. Verify legacy records'),
          ),
        ],
      ),
    ),
  );
}
