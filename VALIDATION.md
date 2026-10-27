# Validation — 0.1.0-dev.1

Updated 2026-10-27. This independent package is implemented locally under
Apache-2.0. It has no Git remote and has not been published. It does not integrate
with Orb or qualify an existing-user migration. Native source is at `096f9cc`;
the original synthetic example/probes are at `aee97e9`. The later separate
qualification fixtures and outcome receipt are under [qualification](qualification/README.md).
Production native code is unchanged by this qualification batch.

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

## Physical iOS and original-install upgrade checks

The user authorized this qualification on 2026-10-27, keeping the personal
phone's biometric enrollment and passcode unchanged. Completed evidence is
captured in the sanitized [qualification receipt](qualification/receipt.json).
These tests use a separate synthetic app identity, never Orb or real secrets.

- **Physical iOS:** iPhone 13 Pro, iOS 26.6 (23G71), Release builds. Actual Flutter
  `biometric_storage 5.0.1` producer (Flutter 3.47.5, build 1) created and verified
  three synthetic records. The user performed those original UI steps. A DN
  1.4.0 consumer (build 2) was installed in place with matching signed application
  identifier, team and default Keychain access group; no uninstall/data reset.
  Its independently retrieved outcome file confirms exact Unicode/emoji/NUL,
  empty and ordinary-text legacy values, pre-copy isolation and verified copying
  into the new namespace. The original strict options use validity=-1, not the
  separate 60-second profile used by some applications.
- **Physical Keychain enforcement:** two hosted XCTest tests passed with Mirroring
  disconnected and the phone unlocked. A fresh noninteractive context returned
  exactly `errSecInteractionNotAllowed` and no bytes for both the original item
  and the new plugin-created item. A same-host unprotected control returned its
  expected bytes. Attribute checks confirmed `whenPasscodeSetThisDeviceOnly` and
  an ACL on both items; they do not decode or prove enrollment invalidation.
- **Android original-install continuity:** actual Flutter `biometric_storage 5.0.1`
  producer on the dedicated API 34 emulator, then DN consumer version 2 with the same test
  certificate and package ID. The first-install timestamp stayed unchanged.
  All three original values were read successfully, a separate new copy was
  explicitly written and read, and every legacy ciphertext SHA-256/length
  matched the producer baseline byte-for-byte. Two subsequent force-stop/relaunch
  cycles of the same read-only consumer build each read all three original values
  and the new copy successfully. Fresh outcome segments were captured per launch;
  the original file hashes remained unchanged afterward.
- **Android enforcement:** two additional instrumentation tests passed. Existing
  legacy keys retain per-use strong-biometric policy; unauthenticated decryption
  must fail with an authentication-specific cause. Corrupt-tag, invalidated-key
  and malformed-IV errors are rejected as false positives by classifier controls.

The initial iOS XCTest run while iPhone Mirroring was active failed with -25293;
it is not counted as a pass. The exact assertions passed after Mirroring was
stopped and the phone unlocked. Apple's [Mirroring note](https://developer.apple.com/documentation/technotes/tn3210-optimizing-your-app-for-iphone-mirroring)
explains why iPhone-only biometric authentication is unavailable during Mirroring.
No companion authentication or weaker policy was added. Attribute queries on
ACL items can also prompt; their contexts are separate from the negative test.

The user reran the **before-copy** isolation check twice after a copy existed.
Both StateError outcomes are retained as failed preconditions, not lost data.
The original consumer batched three protected operations behind one button;
after the user reported repeated prompts, the fixture was changed to one manual
operation per tap, visibly disabled overlapping controls and a cancel control.
This is a test-UI correction, not a change to per-operation authentication.
Physical cancelled replacement, cancelled legacy read, immediate cancellation and
background-cancellation recovery passed, with matching retrieved outcomes and
user observations. A later additional background attempt returned StateError;
the helper cannot distinguish unexpected success from an unexpected biometric
error code in that row. It is retained as failed, not assigned an inferred cause.
The controlled final background retry and subsequent authenticated read passed.
After a cold process launch of the same installed app, the new record and all
three legacy values passed exact reads. Finally, deleting only the new copy
confirmed its absence and that the original Unicode record remained readable.
The user confirmed the physical actions and every final outcome was independently
retrieved from the device. The 09:16 cancellation while Mirroring was active is
not used as physical camera-withheld cancellation proof.

The Android producer initially stalled downloading Gradle with Flutter 3.47.5.
The successful Android host uses the already installed Flutter 3.38.5, retaining
original `biometric_storage 5.0.1` unchanged. The first host polling helper looked
for its result under `cache`; Flutter used `code_cache`. Both producer PASS rows
were subsequently retrieved from the real output file. Neither setup issue is
counted as a plugin failure or an earlier passing test.

## iOS proof boundary

The first unsigned simulator build returned storage_error (-34018). The example
now supplies simulator-only application-identifier/keychain-access-groups derived
from its bundle id. Xcode's expanded simulated entitlements were inspected, and
locally signed installation passed the same Keychain calls. The published example
still needs the consuming developer's real signing configuration. Separate physical qualification hosts were signed locally; no
team identity or provisioning profile is committed.

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

For this additional qualification batch, three read-only reviewers covered
iOS/Keychain enforcement, original-format compatibility and migration boundaries,
and fixture/test assurance. Review found and corrected overly broad Android
negative-error acceptance and differing manual/automatic isolation checks; both
corrections were independently closed and exercised by the final Android run.
Reviewers were reused for focused closure and final evidence review. Per-review
elapsed time and token telemetry are unavailable.

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

The earlier local binary archive baseline (before the additional qualification
fixtures and updated documentation) is 301,675 bytes, SHA-256
`3522742ce17f1c8f7afad6d2fd7f903b11b5094b372931d085b156d7fe4232f2`.
The source archive SHA-256 is
`a1cb2be0056e2e281034dfc23b39297a1f0d1c390fe8ce99c081d5b24bef8ba8`.
Both passed the distribution checker: required licence/notices are retained and
forbidden cache/credential file paths are absent. See [receipt](docs/build-receipt.json).
These are historical local qualification outputs, not published registry artifacts
or hashes of the current complete source tree. Rebuild and recheck the release
artifacts after the final metadata and documentation are selected.

## Reproduce / remaining gates

See [example README](example/README.md) for native run and instrumentation commands.
For package tests, use the installed DN Dart and package configuration; the direct
`test` entry point avoids re-resolving SDK-injected packages through ordinary Pub.
The official plugin build's generated Gradle wrapper can run
`:biometric_storage_kit:testDebugUnitTest` for the five codec tests.

Still required before production migration/release qualification:

- Physical iOS enrollment addition/removal, passcode removal, Touch ID and
  locked-device/backup behavior. Face ID strict-profile enforcement, cancellation,
  recovery, restart and new-copy deletion scope passed above. Security settings
  were left unchanged as requested for this personal phone.
- Physical Android device/Keystore coverage, enrollment invalidation, lockout,
  API 26–29 compatibility and API 30+ variants; hardware backing is not promised.
- Real application upgrades, historical option/name variants, custom access groups
  and app-owned activation/recovery. The separate strict-policy 5.0.1 synthetic
  upgrade/copy fixture passed; that does not qualify an Orb installation.
  Reinstalling the original producer for rollback verification was not run.
- Process death during mutation, storage-full/I/O failure, crash/power-loss
  durability, repeated native host/isolate recreation and full prompt teardown
  interleavings. Cross-process use is not supported/qualified.
- Release-mode consumer/minifier checks and registry download/consumer tests.
- User-authorized repository/metadata/catalogue setup; resolve README document
  and media URLs for registry artifacts that do not include those directories.

No default secret rotation, legacy deletion, wallet migration, or publication is
performed. `device_keys_kit` remains an optional separate signing capability,
not a dependency of this package.
