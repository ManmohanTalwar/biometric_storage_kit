import XCTest
import Security
import LocalAuthentication

/// Hosted by the real DN consumer after public-plugin seeding. No protected
/// item is created by this test, and no production dispatcher is replaced.
final class KeychainEnforcementTests: XCTestCase {
    private let account = "dn-upgrade.aGVsbG8_"
    private let services = ["flutter_biometric_storage",
        "dev.dnplugins.biometric_storage_kit.upgrade-qualification"]

    private func physicalOnly() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Simulator does not establish Keychain ACL enforcement")
        #endif
    }
    private func query(_ service: String, _ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: name,
         kSecUseDataProtectionKeychain as String: true]
    }
    private func noninteractiveRead(_ service: String, _ name: String) -> (OSStatus, CFTypeRef?) {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        context.interactionNotAllowed = true
        defer { context.invalidate() }
        var q = query(service, name)
        q[kSecUseAuthenticationContext as String] = context
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return (SecItemCopyMatching(q as CFDictionary, &result), result)
    }
    func testProtectedRecordsRejectUnauthenticatedReadWithWorkingControl() throws {
        try physicalOnly()
        let controlService = "dev.dnplugins.biometric_qualification.control"
        let controlName = UUID().uuidString
        let value = Data("Synthetic unprotected query control".utf8)
        var control = query(controlService, controlName)
        control[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        control[kSecValueData as String] = value
        XCTAssertEqual(SecItemAdd(control as CFDictionary, nil), errSecSuccess)
        defer { SecItemDelete(query(controlService, controlName) as CFDictionary) }
        let allowed = noninteractiveRead(controlService, controlName)
        XCTAssertEqual(allowed.0, errSecSuccess, "Control must prove query/signing works")
        XCTAssertEqual(allowed.1 as? Data, value)
        for service in services {
            let denied = noninteractiveRead(service, account)
            XCTAssertEqual(denied.0, errSecInteractionNotAllowed,
                "Must be authentication denial, not missing data or invalid entitlements: \(service)")
            XCTAssertNil(denied.1, "Denied read must return no secret bytes")
        }
    }
    func testExistingProtectionMetadata() throws {
        try physicalOnly()
        for service in services {
            var q = query(service, account)
            q[kSecReturnAttributes as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            XCTAssertEqual(SecItemCopyMatching(q as CFDictionary, &result), errSecSuccess)
            let attributes = try XCTUnwrap(result as? [String: Any])
            XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String)
            XCTAssertNotNil(attributes[kSecAttrAccessControl as String])
            XCTAssertEqual(attributes[kSecAttrAccount as String] as? String, account)
            XCTAssertEqual(attributes[kSecAttrService as String] as? String, service)
        }
    }
}
