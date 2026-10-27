package dev.dnplugins.biometric_storage_kit
import android.app.Application
import io.flutter.embedding.engine.plugins.FlutterPlugin

class BiometricStorageKitPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        System.loadLibrary("biometric_storage_kit")
        DNBiometricStorageKitBridge.attach(binding.applicationContext as Application)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        DNBiometricStorageKitBridge.detach()
    }
}
