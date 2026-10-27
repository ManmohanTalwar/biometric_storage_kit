# Changelog

## 0.1.0-dev.1

- Add bounded UTF-8 secret storage with typed errors, cancellation and disposal.
- Protect iOS records with passcode-set, device-only Keychain access and current-set biometrics.
- Protect Android records with per-use strong-biometric Keystore AES-GCM operations.
- Preserve ciphertext and errors instead of automatically recreating invalidated keys.
- Add read-only compatibility for audited biometric_storage 5.0.1 records.
- Guard native callback generation, prompt ownership, main-thread use and malformed Unicode.
- Add a synthetic example, API/codec tests and native enforcement probes.
- Add signed original-install fixtures, physical iPhone enforcement/cancellation/
  restart checks, and Android emulator upgrade/retention checks.
- Split manual qualification steps into one protected operation per tap.

Unpublished development build. These strict-policy synthetic checks passed;
broader device, real application migration and release qualification remain
outstanding. See VALIDATION.md for evidence and exclusions.
