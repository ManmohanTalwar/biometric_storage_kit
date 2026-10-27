# Published-package consumer check

Generate a new DN app with project name `biometric_registry_check`, organization
`dev.dnplugins`, and iOS/Android platforms. Copy this pubspec and main file into
that host. Use `dn pub get` with the explicit hosted dependency; never substitute
a local package path or copied native source. Inspect the plugin cache receipts,
resolved package configuration and native build inputs before counting a pass.
The tested SDK is DN 1.4.0. Keep SDK authentication and personal signing local.

The fixture is synthetic and independent of all legacy-data hosts. Disable Android
backup in its app manifest. On iOS supply NSFaceIDUsageDescription and, only for
the simulator, the example's simulator entitlement file and conditional project
setting. Device builds need the developer's actual authorized signing identity.
DN's unsigned simulator build does not apply Keychain entitlements: build/sign
through Xcode before running Keychain checks on the simulator.

Build Android Release with R8 and iOS Release (unsigned is sufficient for the
compile/link check). Run the Android app on the dedicated enrolled emulator and
supply a biometric for each write/read. Fresh process-filtered `BIOREG` output
must contain five successful outcomes. All data uses the independent
`registry-validation` namespace and `synthetic` name; delete is explicit.

On iOS Simulator this fixture deliberately runs only availability, missing read,
and delete/absence. These three outcomes demonstrate installed-symbol transport
and Keychain integration, not biometric enforcement. The separately recorded
physical iPhone tests supply the limited hardware evidence. Read outcomes from
the new app's temporary `bioreg-results.jsonl`, never from another host or an old
launch. Public release results belong in VALIDATION.md and docs/release-0.1.0.json.
