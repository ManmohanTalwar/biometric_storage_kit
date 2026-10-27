# Biometric storage implementation

Authorized 2026-10-27: implement this separate package, with small local commits.
No GitHub push or catalogue publication is implied. Security/data-retention work
uses independent iOS and Android review before qualification.

## Contract

- Named UTF-8 secret read/write/delete; explicit namespace, prompt text and iOS
  device-unlock reuse duration (0–300 seconds). Strong biometrics only for new data.
- iOS: whenPasscodeSetThisDeviceOnly + biometryCurrentSet, original Swift FFI.
  Explicit biometric authentication before write, ACL-protected Keychain reads.
- Android: Keystore AES-256-GCM key requiring a strong biometric for each crypto
  operation, BiometricPrompt.CryptoObject and generation-safe C++ JNI transport.
  Ciphertext stays in noBackupFilesDir; namespace/name bound through GCM AAD.
- Read returns null only for OS-reported absent data. No read creates keys, rotates
  secrets or deletes ciphertext. Missing does not prove a secret never existed.
- Explicit read-only legacy import source for biometric_storage 5.0.1. Never delete
  or rewrite legacy files/keys. App-owned migration/verification/activation remains
  separate; signed same-identity upgrade testing is required before migration.
- One native operation at a time; overlapping requests fail busy. Cancel/dispose,
  background and isolate changes revoke pending callbacks and prompt ownership.
  Cancellation cannot roll back a mutation already committed. No implicit retry.
- No wallet signing, account authority, key derivation, deleteAll or unprotected mode.

## Delivery slices

1. Official independent scaffold/licence and source references.
2. Dart public contract, bounded input/error/cancellation tests.
3. iOS protected storage + Android crypto-bound storage and safe transport.
4. Native archives and consumer builds, independent security/contract review.
5. Synthetic clean-device demonstrations, README GIFs and explicit evidence limits.

## Acceptance and proof

Dart tests exercise the public storage service with a controlled transport for
validation, busy/dispose/cancel, returned values and typed failures. Native codec
checks exercise real envelope/AAD/Unicode/corruption paths. Native integration must
show a biometric operation succeeds only with an actual authenticated cipher or
ACL context; cancellation/no-enrollment are negative controls. Compilation and
simulator interaction do not prove physical Keychain/Keystore or old-install
continuity. No suitable full security-certification gate exists in this new repo;
record unperformed device, enrollment, passcode, process-death and upgrade tests.

Native implementation uses only public OS APIs and the pinned DN guides. Private
Orb source supplies behavioral requirements, never redistributable code.
