cmake_minimum_required(VERSION 3.22.1)
project("biometric_storage_kit" C CXX)

# libbiometric_storage_kit.so: the bridge Dart opens by this name
# (lib/src/biometric_storage_kit_bindings.dart) and BiometricStorageKitPlugin.kt loads.
add_library(biometric_storage_kit SHARED
    src/main/cpp/dn_biometric_storage_kit_bridge.cpp
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_library(log-lib log)

target_link_libraries(biometric_storage_kit
    ${log-lib}
)

# 16 KB page alignment, required by Google Play on Android 15 and later.
target_link_options(biometric_storage_kit PRIVATE "-Wl,-z,max-page-size=16384")
