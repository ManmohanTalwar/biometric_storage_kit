# Validation — 0.1.0-dev.1

Recorded 2026-10-27. This independent package is implemented locally under
Apache-2.0. It has no Git remote and has not been published. It does not integrate
with Orb or qualify an existing-user migration. Native source is at `096f9cc`;
the synthetic example/probes are at `aee97e9` (subsequent documentation only).

## Environment

- DartNative 1.4.0; Dart 3.12.0-192.0.dev; engine
  `ed0d71411e76bf9558f1c4dc8078f3222e364497`.
- Xcode 26.6 (17F113); iOS 26.5 arm64 iPhone 17 Pro Simulator.
- Dedicated Pixel 6 Pro Android 14/API 34 arm64 emulator; synthetic PIN and
  fingerprint enrollment. No Orb apps installed on either recording device.
- Android compile SDK 36, NDK 28.2.13676358, AGP 8.11.1, Kotlin 2.2.20,
  AndroidX Biometric 1.1.0. API 26/iOS 15 are declared floors, not tested OS coverage.
- Official DN plugin/callback guide pin and public legacy-source hashes are in
  [provenance.json](provenance.json). Private app source informed requirements
  only; no private implementation or real secret was copied.

## Passing checks

| Evidence | Result and boundary |
|---|---|
| Dart analyzer | `lib`, `test`, `example/lib`: no issues |
| Dart API tests | 11 passed: valid/invalid Unicode, limits, distinct missing/empty values, error preservation, busy, cancellation/disposal, prompt range and exact delete scope; controlled transport |
| JVM codec tests | 5 passed: strict UTF-8, unambiguous identity, envelope bounds/version, real AES-GCM roundtrip, wrong AAD and changed ciphertext rejection, legacy IV layout; ordinary JVM keys, not Keystore |
| Official standalone builder | Android AAR arm64-v8a/x86_64, iOS arm64 device and arm64/x86_64 simulator XCFramework compiled successfully |
| Consumer builds | Android Debug APK; iOS Debug simulator through DN preparation and local Xcode signing |
| Android enforcement instrumentation | 1 passed against keys created by the actual plugin: verifies per-use strong-biometric policy, unauthenticated crypto fails, existing ciphertext unchanged |
| Android UI/native integration | Enrolled write and independent read prompts; exact Unicode value; same-turn write/dispose leaves no record; cancelled replacement preserves the prior value; subsequent authenticated read works; explicit delete then missing read |
| Android native-boundary probes | Worker isolate real C initializer rejected without breaking an active main read; 100 main-isolate dispatcher refreshes during that pending read; timed shown-prompt cancellation plus an immediate second-instance availability request passed (success or busy accepted; this is not a second-prompt race test) |
| Android lifecycle/persistence | Setup crossing background rejected with no_foreground_host, resume recovered; cold process restart retained the synthetic record and required authentication to read it |
| iOS UI/native integration | Immediate write/dispose leaves no record; no enrollment reports not_enrolled (-7); explicit write prompt + simulated match stores; Unicode read, cold-process persistence, explicit delete and missing read |
| iOS background cancellation | Backgrounding during a replacement's Face ID prompt returned cancelled; subsequent read retained the earlier value |

## iOS proof boundary

The first unsigned simulator build returned storage_error (-34018). The example
now supplies simulator-only application-identifier/keychain-access-groups derived
from its bundle id. Xcode's expanded simulated entitlements were inspected, and
locally signed installation passed the same Keychain calls. The device build
still needs a real developer signing configuration; no team identity is committed.

Simulator read returned the value **without a second biometric match**, also after
a cold launch. Therefore this run does not prove read authentication, current-set
invalidation, device passcode protection, or hardware storage enforcement.
[Apple's published Security implementation](https://github.com/apple-oss-distributions/Security/blob/db15acbe6a7f257a859ad9a3bb86097bfe0679d9/keychain/securityd/SecDbKeychainItemV7.m#L652-L656)
sets a simulator-only no-constraints path when wrapping keys. This is consistent
with the result; it is not evidence that the published source hash matches the
installed runtime. The plugin retains the OS ACL implementation. No extra read
prompt or weaker ACL was introduced to disguise this limitation.

## Independent review and corrections

Separate read-only iOS/lifecycle, Android/security and public-contract reviews
covered the complete candidate. All blocking source findings were corrected and
independently re-reviewed:

- Reserve native requests before returning to Dart: immediate cancellation cannot
  miss a deferred request. Exercised on both platforms.
- Rebind only from the living Dart isolate after native host reset and fail stale
  pending futures. Source reviewed; exact retained-isolate host-recreation matrix
  is not fully exercised.
- Reject malformed UTF-16 before transport and use strict Android encoding.
  Dart and native codec regression tests pass.
- Send Android AAD only after the cipher is authorized; real Keystore write/read
  and unauthenticated negative control pass.
- Hold Android prompt ownership while cancellation drains; retire destroyed hosts,
  reject paused/state-saved hosts and clear synchronous setup failures. Real timed
  cancel/availability and background-setup checks pass. Immediate replacement by
  a second biometric prompt, deterministic fragment teardown and session-reset
  interleavings remain untested.
- Publish the generation function atomically and reject off-main entry before
  changing dispatcher state. Worker-isolate/repeated-refresh probe passes;
  ThreadSanitizer and a sustained concurrent stress run were not performed.

The first timed-cancellation **test helper** reported failure because it settled
its own completion before the observer request returned. That helper was fixed
and rerun successfully; the earlier cancelled write had preserved the secret.
No failed or interrupted run is counted as a pass.

## Recordings

[Android GIF](docs/media/android-demo.gif) uses the emulator host recorder, 24 fps,
then a 12 fps/360 px GIF. [iOS GIF](docs/media/ios-demo.gif) uses RocketSim at 24 fps,
then a 12 fps/360 px GIF; only idle lead-in/out was trimmed. Both are real example
flows with synthetic data. Full-range contact sheets were inspected: no Orb apps,
private content or unrelated notifications appear. Exact hashes are in
[media metadata](docs/media/recordings.json).

The iOS caption states its Keychain enforcement limitation. Marionette was not
added: its audited Flutter binding does not drive the native DN UI. Recordings
are demonstrations, not security certification.

## Artifact receipt

The final local binary archive is 301,675 bytes, SHA-256
`3522742ce17f1c8f7afad6d2fd7f903b11b5094b372931d085b156d7fe4232f2`.
The source archive SHA-256 is
`a1cb2be0056e2e281034dfc23b39297a1f0d1c390fe8ce99c081d5b24bef8ba8`.
Both passed the distribution checker: required licence/notices are retained and
forbidden cache/credential file paths are absent. See [receipt](docs/build-receipt.json).
These are local qualification outputs, not published registry artifacts.

## Reproduce / remaining gates

See [example README](example/README.md) for native run and instrumentation commands.
For package tests, use the installed DN Dart and package configuration; the direct
`test` entry point avoids re-resolving SDK-injected packages through ordinary Pub.
The official plugin build's generated Gradle wrapper can run
`:biometric_storage_kit:testDebugUnitTest` for the five codec tests.

Still required before production migration/release qualification:

- Physical iOS read denial before authentication, Face ID/Touch ID outcomes,
  enrollment addition/removal, passcode removal and accessibility/backup behavior.
- Physical Android device/Keystore coverage, enrollment invalidation, lockout,
  API 26–29 compatibility and API 30+ variants; hardware backing is not promised.
- Same-signed-identity upgrades from actual biometric_storage 5.0.1 installations,
  original names/access groups, exact secret continuity and app-owned activation.
- Process death during mutation, storage-full/I/O failure, crash/power-loss
  durability, repeated native host/isolate recreation and full prompt teardown
  interleavings. Cross-process use is not supported/qualified.
- Release-mode consumer/minifier checks and registry download/consumer tests.
- User-authorized repository/metadata/catalogue setup; resolve README document
  and media URLs for registry artifacts that do not include those directories.

No default secret rotation, legacy deletion, wallet migration, or publication is
performed. `device_keys_kit` remains an optional separate signing capability,
not a dependency of this package.
