# Third-party notices

Scaffold: DartNative 1.4.0 official plugin template; no SDK runtime source or
binaries redistributed. Original FFI transport adapted from Apache-2.0
quick_actions_kit, Copyright 2026 the quick_actions_kit contributors.

biometric_storage 5.0.1 was consulted for API and persisted format compatibility;
new implementation is original. Its MIT licence is retained below. Its Android
CryptographyManager reference additionally credits the Android Open Source Project
under Apache-2.0 (see LICENSE). No private Orb implementation is copied.

Android native dependencies are resolved by the consuming application and are
not bundled into this plugin's AAR:

- androidx.annotation:annotation:1.7.1 — Apache-2.0.
  https://dl.google.com/dl/android/maven2/androidx/annotation/annotation/1.7.1/annotation-1.7.1.pom
- androidx.biometric:biometric:1.1.0 — Apache-2.0.
  https://dl.google.com/dl/android/maven2/androidx/biometric/biometric/1.1.0/biometric-1.1.0.pom

Copyright The Android Open Source Project. The full Apache-2.0 licence accompanies
this package in LICENSE. These are direct declarations, not a fixed list of all
transitive versions selected by a consuming app. The Dart ffi dependency is
resolved separately under its own BSD-3-Clause licence; the DartNative runtime
is supplied by the consuming developer's licensed SDK, not this plugin.

MIT License

Copyright (c) 2019 Herbert Poul (@hpoul)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
