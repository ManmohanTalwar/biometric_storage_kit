# Synthetic biometric storage example

No account, real secret, Orb asset, or private data is needed. Use dedicated clean
devices. Store, read and delete operate only on this example's synthetic record.

## Build

Run `dn pub get` in the package and example, using DartNative 1.4.0. Android:

```sh
dn build apk --debug
```

Install that APK only on the intended emulator. Enroll a synthetic fingerprint
through Android Settings and use the emulator's fingerprint controls. Always
select the device explicitly when installing, recording or sending a match.

For iOS, the example includes simulator-only Keychain entitlements. A
`--no-codesign` build lacks the identity needed for Keychain and fails with -34018.
After `dn build ios --simulator --debug --no-codesign` prepares the build inputs,
perform a locally signed simulator build:

```sh
# DN_SDK_ROOT is your installed DartNative SDK; DEMO_UDID is the clean simulator.
cd ios
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
  -sdk iphonesimulator -destination "platform=iOS Simulator,id=$DEMO_UDID,arch=arm64" \
  FLUTTER_ROOT="$DN_SDK_ROOT" CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES
```

Install the resulting Xcode build product, not the earlier unsigned product.
No developer account, real team identifier or provisioning update is needed for
this simulator path. Physical devices require normal real signing; simulator
entitlements are conditionally excluded from device builds. Enable simulated
Face ID in Simulator's Features menu. Simulated enrollment is not physical proof.

## Checks

- `Check immediate cancellation`: delete an isolated synthetic probe record,
  request a write and dispose in the same Dart turn, then verify cancellation
  and absence. No prompt or write should occur.
- Store and read the Unicode demo value. Every read/write needs authentication.
- Cancel a read: no new value should appear. Cancel a replacement: the existing
  stored value must remain. Read again with authentication to verify it.
- Background during a prompt, resume, and perform a fresh operation.

Build with `--dart-define=BIOMETRIC_TEST_PROBES=true` to reveal two extra controls:
worker-isolate rejection plus 100 main-isolate dispatcher refreshes during a
pending read, and timed prompt cancellation followed by an immediate second
instance request. These controls are hidden from the normal README demo.

After storing the synthetic record through the actual Android plugin, build and
run `KeystoreEnforcementTest` on that same emulator. The test inspects production
key policy, attempts unauthenticated crypto, and checks ciphertext is unchanged:

```sh
cd android
FLUTTER_STORAGE_BASE_URL=https://cdn.dartnative.com \
  ./gradlew :app:assembleDebugAndroidTest
# Install the test APK with adb -s "$DEMO_SERIAL" install -r -t <test-apk>.
adb -s "$DEMO_SERIAL" shell am instrument -w \
  -e class dev.dnplugins.biometric_storage_kit_example.KeystoreEnforcementTest \
  dev.dnplugins.biometric_storage_kit_example.test/androidx.test.runner.AndroidJUnitRunner
```

Do not run these against an app or device containing real user secrets. The test
requires an enrolled API 30+ emulator/device and a record already created by the
plugin. It does not stand in for physical hardware or upgrade qualification.
