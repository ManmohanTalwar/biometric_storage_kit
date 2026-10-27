package dev.dnplugins.biometric_storage_kit

import android.os.Build
import androidx.annotation.Keep

/**
 * The Android APIs behind biometric_storage_kit's native functions.
 *
 * Each method is called from the C++ bridge (src/main/cpp) over JNI, by
 * name, which is why every one is @Keep and @JvmStatic: shrinking must not
 * rename or drop them. To add a function, add a method here and its C++
 * and Dart sides.
 */
object DNBiometricStorageKitBridge {
    @Keep
    @JvmStatic
    fun platformVersion(): String = "Android " + Build.VERSION.RELEASE
}
