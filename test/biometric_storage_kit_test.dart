import 'package:biometric_storage_kit/biometric_storage_kit.dart';
import 'package:test/test.dart';

void main() {
  // The native functions exist only in an iOS or Android build. On this
  // machine loadSymbols() does nothing and the API says so plainly, which
  // is what the app's generated registrant relies on.
  test('loadSymbols is harmless where there is no native code', () {
    BiometricStorageKitBindings.loadSymbols();
    expect(BiometricStorageKitBindings.instance.isLoaded, isFalse);
  });

  test('platformVersion names the platforms it needs', () {
    expect(() => BiometricStorageKit().platformVersion(), throwsUnsupportedError);
  });
}
