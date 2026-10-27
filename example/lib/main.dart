import 'dart:async';
import 'dart:isolate';
import 'package:dartnative/dartnative.dart';
import 'package:biometric_storage_kit/biometric_storage_kit.dart';
import 'dartnative_plugin_registrant.dart';

void main() {
  DartNativePluginRegistrant.registerAll();
  runApp(const BiometricDemo());
}

class BiometricDemo extends StatefulWidget {
  const BiometricDemo({super.key});
  @override
  State<BiometricDemo> createState() => _BiometricDemoState();
}

class _BiometricDemoState extends State<BiometricDemo> {
  final storage = BiometricStorage(namespace: 'public-demo');
  String status = 'Ready';
  String result = 'No secret read';
  bool busy = false;
  static const demoValue = 'Demo secret • नमस्ते';
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = 'Waiting…';
    });
    try {
      await action();
    } on BiometricStorageException catch (error) {
      status =
          'Result: ${error.code}${error.nativeCode == null ? '' : ' (${error.nativeCode})'}';
    } catch (_) {
      status = 'Operation failed';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    storage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Biometric storage')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text('Synthetic data only'),
          Text(status),
          Text(result),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => run(() async {
              status =
                  'Biometrics: ${(await storage.checkAvailability()).name}';
            }),
            child: const Text('Check biometrics'),
          ),
          ElevatedButton(
            onPressed: () => run(() async {
              await storage.write('demo-secret', demoValue);
              status = 'Demo secret stored';
            }),
            child: const Text('Store demo secret'),
          ),
          ElevatedButton(
            onPressed: () => run(() async {
              result = 'No secret read';
              final value = await storage.read('demo-secret');
              result = value == null
                  ? 'No secret stored'
                  : value == demoValue
                  ? 'Verified: नमस्ते'
                  : 'Value differs';
              status = 'Read complete';
            }),
            child: const Text('Read demo secret'),
          ),
          ElevatedButton(
            onPressed: () => run(() async {
              await storage.delete('demo-secret');
              result = 'No secret read';
              status = 'Demo secret deleted';
            }),
            child: const Text('Delete demo secret'),
          ),
          ElevatedButton(
            onPressed: () => run(() async {
              final probe = BiometricStorage(namespace: 'cancellation-demo');
              await probe.delete('probe');
              final pending = probe.write('probe', 'Never persist this');
              probe
                  .dispose(); // Same Dart turn, before native queue activation.
              try {
                await pending;
                status = 'FAILED: cancellation ignored';
              } on BiometricStorageException catch (error) {
                final verifier = BiometricStorage(
                  namespace: 'cancellation-demo',
                );
                try {
                  final absent = await verifier.read('probe') == null;
                  status = error.code == 'cancelled' && absent
                      ? 'Immediate cancel verified'
                      : 'FAILED: cancellation check';
                } finally {
                  verifier.dispose();
                }
              }
            }),
            child: const Text('Check immediate cancellation'),
          ),
          if (const bool.fromEnvironment('BIOMETRIC_TEST_PROBES')) ...[
            ElevatedButton(
              onPressed: () => run(() async {
                final pending = storage.read('demo-secret');
                // Invoke the real C entry point off-main while the read owns a
                // prompt, then refresh repeatedly from the living main isolate.
                final rejected = await Isolate.run(() {
                  try {
                    BiometricStorageKitBindings.loadSymbols();
                    return false;
                  } on BiometricStorageException catch (error) {
                    return error.code == 'unsupported_runtime';
                  }
                });
                for (var i = 0; i < 100; i++) {
                  BiometricStorageKitBindings.loadSymbols();
                }
                final value = await pending;
                status = rejected && value == demoValue
                    ? 'Worker rejection verified'
                    : 'FAILED: worker check';
              }),
              child: const Text('Verify worker rejection'),
            ),
            ElevatedButton(
              onPressed: () => run(() async {
                final observer = BiometricStorage(namespace: 'public-demo');
                final pending = storage.write(
                  'demo-secret',
                  'Replacement must not persist',
                );
                final next = Completer<bool>();
                Timer(const Duration(seconds: 2), () async {
                  storage.cancelPending();
                  try {
                    await observer.checkAvailability();
                    next.complete(true);
                  } on BiometricStorageException catch (error) {
                    next.complete(error.code == 'busy');
                  } catch (_) {
                    next.complete(false);
                  }
                });
                var cancelled = false;
                try {
                  await pending;
                } on BiometricStorageException catch (error) {
                  cancelled = error.code == 'cancelled';
                }
                final ownership = await next.future;
                // The user taps Read next and authenticates to check preservation.
                observer.dispose();
                status = cancelled && ownership
                    ? 'Prompt cancellation verified'
                    : 'FAILED: prompt check';
              }),
              child: const Text('Verify prompt cancellation'),
            ),
          ],
          ElevatedButton(
            onPressed: storage.cancelPending,
            child: const Text('Cancel operation'),
          ),
        ],
      ),
    ),
  );
}
