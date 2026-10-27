/// Biometric-protected secret storage for DartNative using iOS Keychain and Android Keystore.
library;

// The plugin's API.
export 'src/biometric_storage_kit.dart' show BiometricStorageKit;
// The native symbol loader. The app's generated
// lib/dartnative_plugin_registrant.dart calls it before runApp, because
// pubspec.yaml names it under `dartnative: registrant:`.
export 'src/biometric_storage_kit_bindings.dart' show BiometricStorageKitBindings;
