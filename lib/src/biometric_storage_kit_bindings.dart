// The native functions this plugin calls, looked up once at startup.
//
// iOS: the Swift under ios/Classes is compiled into the app itself, so
// DynamicLibrary.process() finds every @_cdecl function by name.
// Android: android/CMakeLists.txt builds libbiometric_storage_kit.so from the C++
// bridge under android/src/main/cpp, and BiometricStorageKitPlugin.kt loads it when the
// engine starts, so the open() below finds it already loaded.
//
// To add a function: a typedef pair and a lookup here, the function in
// ios/Classes and in android/src/main/cpp (plus its Kotlin method), and a
// method on the API class in biometric_storage_kit.dart.
library;

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

typedef _PlatformVersionNative = Pointer<Utf8> Function();
typedef _PlatformVersionDart = Pointer<Utf8> Function();

final class BiometricStorageKitBindings {
  BiometricStorageKitBindings._();

  static final BiometricStorageKitBindings instance = BiometricStorageKitBindings._();

  /// Called by the app's generated registrant on startup. Safe to call more
  /// than once, and safe on a platform this plugin has no native code for,
  /// where it does nothing: `dn test` on this machine still runs.
  static void loadSymbols() => instance.load();

  /// Whether the native functions were found. False on any platform other
  /// than iOS and Android.
  bool get isLoaded => _loaded;
  bool _loaded = false;

  late final _PlatformVersionDart _platformVersion;

  /// The native function, callable once [isLoaded] is true.
  Pointer<Utf8> platformVersion() => _platformVersion();

  void load() {
    if (_loaded) return;
    final DynamicLibrary library;
    if (Platform.isAndroid) {
      library = DynamicLibrary.open('libbiometric_storage_kit.so');
    } else if (Platform.isIOS) {
      library = DynamicLibrary.process();
    } else {
      return;
    }
    _platformVersion = library.lookupFunction<_PlatformVersionNative, _PlatformVersionDart>(
      'DNBiometricStorageKitPlatformVersion',
    );
    _loaded = true;
  }
}
