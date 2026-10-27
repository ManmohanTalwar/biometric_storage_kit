import 'package:dartnative/dartnative.dart';
import 'package:biometric_storage_kit/biometric_storage_kit.dart';

import 'dartnative_plugin_registrant.dart';

void main() {
  // Platform bindings + (once you add plugins) their FFI symbols. Keep this
  // as the FIRST line of main() — see lib/dartnative_plugin_registrant.dart.
  DartNativePluginRegistrant.registerAll();
  // App-wide system chrome default for the white template: dark status-bar
  // icons over the light background, transparent strips. Screens can override
  // in initState; the navigator restores this default on pop.
  SystemChrome.defaultStyle = const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  );
  runApp(const HomeScreen());
}

/// Starter screen — replace this with your own UI.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // One call into the plugin's native code, on both platforms. The
    // registrant bound the function before runApp; see
    // ../lib/src/biometric_storage_kit_bindings.dart.
    final String platform = BiometricStorageKit().platformVersion();
    return Scaffold(
      // White-by-design screen: declare the light trait so system materials
      // (keyboard, glass) stay light even when the device is in Dark Mode.
      brightness: Brightness.light,
      appBar: AppBar(
        title: const Text('DartNative'),
        // No backgroundColor: on iOS 26 this is the fully CLEAR glass bar
        // (the system scroll-edge ramp keeps it legible); elsewhere the
        // platform's default light bar over the white screen.
      ),
      backgroundColor: const Color(0xFFFFFFFF),
      body: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '👋  Welcome to DartNative',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 10),
            Text(
              'Running on $platform',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Edit lib/main.dart to build your app. '
              'See README.md to swap the app icon / splash logo, '
              'and dartpub.dev for plugins.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
