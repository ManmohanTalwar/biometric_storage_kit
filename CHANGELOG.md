# Changelog

## 0.1.0

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

Initial release with limited device qualification. Strict-policy synthetic checks passed;
broader device and real application migration qualification remain outstanding.
See [validation](https://github.com/ManmohanTalwar/biometric_storage_kit/blob/main/VALIDATION.md)
for evidence and exclusions.
