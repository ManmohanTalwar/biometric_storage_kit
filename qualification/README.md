# Physical enforcement and original-install qualification

These are standalone synthetic fixtures, not a production migration or part of
this plugin's runtime. Never point them at an existing application identity.
The original producer uses the actual public `biometric_storage: 5.0.1`; no
storage implementation is copied or re-created. The consumer uses this package.

Both fixtures use `dev.dnplugins.biometric_upgrade_fixture` on Android and
`dev.dnplugins.biometricUpgradeFixture` on iOS. They must share signing identity
and increase build/version code from 1 to 2. Install the consumer **over** the
producer: never uninstall, clear data or silently change signing to resolve an
installation error. Disable Android backup in both generated fixture hosts.

Original options: authenticationRequired=true, validity=-1,
androidBiometricOnly=true, darwinBiometricOnly=true. This tests that exact strict
profile, not every historical configuration or an application wrapper's policy.
Records include text, empty string, and Unicode/emoji/NUL content with an exact
safe dotted/base64URL-shaped name. Their values are synthetic and public.

## Execution order

1. Generate each platform shell using the stated installed SDK and copy the
   corresponding fixture source and manifest. Resolve the original dependency
   against its included lockfile. Use FlutterFragmentActivity for Android's
   producer and an AppCompat theme. Keep all real signing configuration local.
2. On iOS set NSFaceIDUsageDescription and sign both apps with the same bundle
   identity, App ID prefix and authorized default Keychain group. Compare built
   entitlements, not just project settings. On Android compare package IDs,
   versions and signing certificate SHA-256 hashes before installing.
3. Install the producer. Create and verify all three records through its UI and
   real biometric prompts. Preserve pass/fail output. On Android record file
   hashes/lengths and package UID/first-install time before the update.
4. Install the DN consumer in place. Run cases 1 and 2 (legacy verification and
   absence of new-format copies) before case 3 explicitly copies and verifies.
5. Run hosted iOS XCTest from `ios/KeychainEnforcementTests.swift` after case 3
   and **before case 9**. It requires real existing protected records. A fresh
   noninteractive context must return errSecInteractionNotAllowed with no data,
   while an unprotected test-owned control succeeds. Simulator is skipped.
6. Cover the camera / withhold biometric input for cases 5 and 6. The timer
   cancels at three seconds. Repeat case 1 after case 5; run case 4 immediately
   after case 6 to prove retention, not just cancellation.
7. For case 7, background while authentication is pending, then return. Record
   that observation alongside PASS: a cancellation outcome alone cannot identify
   its cause. Case 4 must then succeed. Run immediate-cancellation case 8.
8. Cold-launch and repeat cases 1 and 4. Recheck Android legacy hashes; they must
   match the original producer baseline. Case 9 deletes only the new copy and
   must leave the legacy value readable. Reinstalling the original producer at
   build/version 3 and verifying records supplies an additional preservation
   witness, without deleting or rewriting them.

The consumer writes outcome-only JSON lines to its temporary directory and
stdout (`BIOQUAL`); no secret values, personal signing details or device IDs are
included. Keep raw build/device/provisioning logs outside Git. Public receipts
record sanitized identity comparisons and artifact hashes, not personal data.

Do not alter a personal device's passcode or biometric enrollment. Enrollment
invalidation, passcode removal, Touch ID, lockout, backup/restore, alternative
legacy policies and real application activation remain separate qualification.
These fixture sources and instructions are preparation, not evidence of a pass;
executed results belong in the root VALIDATION.md.
