import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartnative/dartnative.dart';
import 'package:biometric_storage_kit/biometric_storage_kit.dart';
import 'dartnative_plugin_registrant.dart';

const fixtureName = 'dn-upgrade.aGVsbG8_';
const emptyName = 'dn-upgrade-empty';
const textName = 'dn-upgrade-text';
const fixtureValue = 'Migration fixture • नमस्ते • 🔐\u0000end';
const textValue = 'Synthetic migration record 2026';
void main() {
  DartNativePluginRegistrant.registerAll();
  runApp(const UpgradeQualification());
}

class UpgradeQualification extends StatefulWidget {
  const UpgradeQualification({super.key});
  @override
  State<UpgradeQualification> createState() => _UpgradeState();
}

class _UpgradeState extends State<UpgradeQualification> {
  final storage = BiometricStorage(namespace: 'upgrade-qualification');
  var status = 'Ready: DartNative consumer';
  var busy = false;
  var legacyStep = 0;
  var copyStep = 0;
  String? stagedCopy;
  static const legacyLabels = [
    '1a. Read legacy Unicode',
    '1b. Read legacy empty',
    '1c. Read legacy text',
  ];
  static const copyLabels = [
    '3a. Read source for copy',
    '3b. Write new copy',
    '3c. Verify new copy',
  ];
  Future<bool> run(String name, Future<void> Function() action) async {
    if (busy) return false;
    setState(() {
      busy = true;
      status = 'Running $name';
    });
    String? code;
    var passed = false;
    try {
      await action();
      passed = true;
    } on BiometricStorageException catch (e) {
      code = e.code;
    } catch (e) {
      code = e.runtimeType.toString();
    }
    final event = jsonEncode({
      'case': name,
      'passed': passed,
      'error': ?code,
      'utc': DateTime.now().toUtc().toIso8601String(),
    });
    // Machine-readable outcomes, no stored values or device identifiers.
    print('BIOQUAL $event');
    try {
      await File(
        '${Directory.systemTemp.path}/bioqual-results.jsonl',
      ).writeAsString('$event\n', mode: FileMode.append, flush: true);
    } catch (_) {
      print('BIOQUAL evidence-file-unavailable');
    }
    status =
        '${passed ? 'PASS' : 'FAIL'}: $name${code == null ? '' : ' ($code)'}';
    if (mounted) setState(() => busy = false);
    return passed;
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid &&
        const bool.fromEnvironment('QUALIFICATION_AUTORUN')) {
      Future<void>.delayed(Duration.zero, () async {
        for (var i = 0; i < 3; i++) {
          if (!await run('legacy-step-$legacyStep', legacy)) return;
        }
        if (!await run('isolation-before-copy', isolation)) return;
        for (var i = 0; i < 3; i++) {
          if (!await run('copy-step-$copyStep', copyNext)) return;
        }
        await run('new-read', () async {
          require(await storage.read(fixtureName) == fixtureValue);
        });
      });
    }
  }

  void require(bool condition) {
    if (!condition) throw StateError('Verification mismatch');
  }

  Future<void> legacy() async {
    final names = [fixtureName, emptyName, textName];
    final values = [fixtureValue, '', textValue];
    require(
      await storage.readLegacyFlutter(names[legacyStep]) == values[legacyStep],
    );
    legacyStep = (legacyStep + 1) % names.length;
  }

  Future<void> isolation() async {
    require(await storage.read(fixtureName) == null);
    require(await storage.read(emptyName) == null);
    require(
      await storage.readLegacyFlutter('dn-upgrade-never-created') == null,
    );
    final other = BiometricStorage(namespace: 'upgrade-other');
    try {
      require(await other.read(fixtureName) == null);
    } finally {
      other.dispose();
    }
  }

  Future<void> copyNext() async {
    if (copyStep == 0) {
      final old = await storage.readLegacyFlutter(fixtureName);
      require(old == fixtureValue);
      stagedCopy = old;
      copyStep = 1;
    } else if (copyStep == 1) {
      require(stagedCopy == fixtureValue);
      await storage.write(fixtureName, stagedCopy!);
      stagedCopy = null;
      copyStep = 2;
    } else {
      require(await storage.read(fixtureName) == fixtureValue);
      copyStep = 0;
    }
  }

  Future<void> cancelled(
    Future<Object?> Function() action, {
    bool timed = true,
  }) async {
    final timer = timed
        ? Timer(const Duration(seconds: 3), storage.cancelPending)
        : null;
    try {
      await action();
      throw StateError('Unexpected success');
    } on BiometricStorageException catch (e) {
      require(e.code == 'cancelled');
    } finally {
      timer?.cancel();
    }
  }

  Widget button(String title, String name, Future<void> Function() action) =>
      ElevatedButton(
        onPressed: busy ? null : () => run(name, action),
        child: Text(title),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Storage upgrade checks')),
    body: Padding(
      padding: const EdgeInsets.all(18),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const Text('Synthetic records only. One operation per tap.'),
            const Text(
              'Face ID pauses app interaction until you approve or cancel.',
            ),
            Text(status),
            if (busy)
              ElevatedButton(
                onPressed: storage.cancelPending,
                child: const Text('Cancel current check'),
              ),
            const SizedBox(height: 12),
            button(legacyLabels[legacyStep], 'legacy-step-$legacyStep', legacy),
            button(
              '2. Check isolation before copy',
              'isolation-before-copy',
              isolation,
            ),
            button(copyLabels[copyStep], 'copy-step-$copyStep', copyNext),
            button('4. Read new record', 'new-read', () async {
              require(await storage.read(fixtureName) == fixtureValue);
            }),
            button(
              '5. Cancel legacy read (cover camera)',
              'cancel-legacy-read',
              () => cancelled(() => storage.readLegacyFlutter(fixtureName)),
            ),
            button(
              '6. Cancel replacement (cover camera)',
              'cancel-replacement',
              () => cancelled(
                () => storage.write(fixtureName, 'Must never replace fixture'),
              ),
            ),
            button(
              '7. Read then background app',
              'background-cancel-read',
              () => cancelled(() => storage.read(fixtureName), timed: false),
            ),
            button('8. Immediate cancellation', 'immediate-cancel', () async {
              final probe = BiometricStorage(namespace: 'upgrade-cancel-probe');
              await probe.delete('never-persist');
              final pending = probe.write(
                'never-persist',
                'Synthetic cancelled write',
              );
              probe.dispose();
              var denied = false;
              try {
                await pending;
              } on BiometricStorageException catch (e) {
                denied = e.code == 'cancelled';
              }
              final verify = BiometricStorage(
                namespace: 'upgrade-cancel-probe',
              );
              try {
                require(denied && await verify.read('never-persist') == null);
              } finally {
                verify.dispose();
              }
            }),
            button('9. Delete only new copy', 'delete-current-only', () async {
              await storage.delete(fixtureName);
              require(await storage.read(fixtureName) == null);
              require(
                await storage.readLegacyFlutter(fixtureName) == fixtureValue,
              );
            }),
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    storage.dispose();
    super.dispose();
  }
}
