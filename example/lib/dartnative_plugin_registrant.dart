// GENERATED FILE — DO NOT EDIT BY HAND.
//
// Scaffolded by `dn create` and regenerated on every `dn pub get` to load the
// FFI symbols of your dartnative_* plugins (see FlutterProject.injectPlugins →
// _writeDartNativePluginRegistrant in the dn tool). Adding or removing a
// dartnative_* dependency updates this file automatically — no manual step.
//
// To hand-own this file, delete the header line above; the CLI then stops
// overwriting it.
import 'dart:io' show Platform;

import 'package:dartnative/dartnative.dart';
import 'package:dartnative_ios/dartnative_ios.dart';
import 'package:dartnative_android/dartnative_android.dart';

abstract final class DartNativePluginRegistrant {
  /// Registers the platform bindings and loads every dartnative_* plugin's FFI
  /// symbols. Call once as the first line of `main()`, before [runApp].
  static void registerAll() {
    registerNativeBindings(
      Platform.isAndroid
          ? AndroidNativeBindings.instance
          : IOSNativeBindings.instance,
    );
  }
}
