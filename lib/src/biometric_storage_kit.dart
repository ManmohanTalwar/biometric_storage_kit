import 'package:ffi/ffi.dart';

import 'biometric_storage_kit_bindings.dart';

/// Biometric-protected secret storage for DartNative using iOS Keychain and Android Keystore.
class BiometricStorageKit {
  /// The operating system and its version as the phone reports it:
  /// "iOS 26.0" or "Android 15".
  ///
  /// One native call. The native side returns a pointer to a string it keeps
  /// for the life of the app, so nothing is freed here; `toDartString()`
  /// copies the bytes into a Dart String.
  String platformVersion() {
    final BiometricStorageKitBindings bindings = BiometricStorageKitBindings.instance..load();
    if (!bindings.isLoaded) {
      throw UnsupportedError('biometric_storage_kit has native code for iOS and Android only.');
    }
    return bindings.platformVersion().toDartString();
  }
}
