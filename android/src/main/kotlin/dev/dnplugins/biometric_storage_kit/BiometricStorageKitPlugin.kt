package dev.dnplugins.biometric_storage_kit

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * The entry point the app registers when its engine starts, because
 * pubspec.yaml names it under `dartnative: plugin: platforms: android:`.
 *
 * Its one job is to load libbiometric_storage_kit.so before any Dart runs, which
 * also runs the C++ bridge's JNI_OnLoad on this thread. Nothing here talks
 * to Dart: Dart calls the library's C functions directly.
 */
class BiometricStorageKitPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        try {
            System.loadLibrary("biometric_storage_kit")
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.e("BiometricStorageKit", "libbiometric_storage_kit.so did not load: ${e.message}")
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Nothing to undo: the library stays loaded.
    }
}
