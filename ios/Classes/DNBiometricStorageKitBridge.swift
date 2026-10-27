// The native side of biometric_storage_kit on iOS.
//
// Every function marked @_cdecl here is compiled into the app and found by
// name from Dart (lib/src/biometric_storage_kit_bindings.dart) through
// DynamicLibrary.process(). Nothing imports Flutter and there is no method
// channel: Dart calls these functions directly.
//
// To add a function: write it here as @_cdecl("DNBiometricStorageKitYourName")
// with C-compatible argument and return types, add the matching lookup to
// the bindings file, and the same function to the Android bridge.

import Foundation
import UIKit

/// The operating system and its version, "iOS 26.0", as a pointer to a C
/// string this file keeps for the life of the app, so the Dart side never
/// frees it. A string that changes per call needs a different pattern: see
/// the plugin guide on string lifetimes.
private let platformVersion: UnsafeMutablePointer<CChar> =
    strdup("iOS " + UIDevice.current.systemVersion)!

@_cdecl("DNBiometricStorageKitPlatformVersion")
public func DNBiometricStorageKitPlatformVersion() -> UnsafePointer<CChar> {
    return UnsafePointer(platformVersion)
}
