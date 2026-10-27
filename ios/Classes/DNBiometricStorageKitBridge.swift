// Copyright 2026 the biometric_storage_kit contributors.
// SPDX-License-Identifier: Apache-2.0
import Foundation
import Security
import LocalAuthentication
import UIKit

private typealias Dispatcher = @convention(c) (Int64, Int32, UnsafePointer<CChar>) -> Void
private let slot: UnsafeMutablePointer<Int64> = {
    let p = UnsafeMutablePointer<Int64>.allocate(capacity: 1); p.pointee = 0; return p
}()
private var registered = false
private var session: UInt64 = 0
private let worker = DispatchQueue(label: "dev.dnplugins.biometric-storage", qos: .userInitiated)
private var active: Operation?
private var backgroundObserver: NSObjectProtocol?

private final class Operation {
    let id: Int64
    let session: UInt64
    let context = LAContext()
    private let lock = NSLock()
    private var stopped = false
    init(_ id: Int64, _ session: UInt64) { self.id = id; self.session = session }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancel() { lock.lock(); stopped = true; lock.unlock(); context.invalidate() }
}
private struct Failure: Error {
    let code: String; let nativeCode: Int?
    init(_ code: String, _ nativeCode: Int? = nil) { self.code = code; self.nativeCode = nativeCode }
}
private func send(_ id: Int64, value: Any? = nil, error: Failure? = nil) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard slot.pointee != 0 else { return }
    var payload: [String: Any] = ["value": value ?? NSNull()]
    if let error = error {
        var details: [String: Any] = ["code": error.code, "message": "Protected storage operation failed (\(error.code))."]
        if let code = error.nativeCode { details["nativeCode"] = code }
        payload = ["error": details]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let text = String(data: data, encoding: .utf8) else { return }
    let pointer = slot.pointee
    text.withCString { unsafeBitCast(pointer, to: Dispatcher.self)(id, 0, $0) }
}
private func finish(_ op: Operation, value: Any? = nil, error: Failure? = nil) {
    DispatchQueue.main.async {
        guard active === op, op.session == session else { return }
        active = nil
        op.context.invalidate()
        send(op.id, value: value, error: error)
    }
}
private func laFailure(_ error: Error?) -> Failure {
    let n = error as NSError?
    guard n?.domain == LAError.errorDomain, let code = n?.code else { return Failure("authentication_failed") }
    switch code {
    case LAError.userCancel.rawValue, LAError.appCancel.rawValue, LAError.systemCancel.rawValue: return Failure("cancelled", code)
    case LAError.biometryNotEnrolled.rawValue: return Failure("not_enrolled", code)
    case LAError.biometryNotAvailable.rawValue: return Failure("unavailable", code)
    case LAError.biometryLockout.rawValue: return Failure("locked_out", code)
    case LAError.passcodeNotSet.rawValue: return Failure("passcode_not_set", code)
    case LAError.invalidContext.rawValue: return Failure("invalid_context", code)
    case LAError.notInteractive.rawValue: return Failure("interaction_not_allowed", code)
    default: return Failure("authentication_failed", code)
    }
}
private func statusFailure(_ status: OSStatus) -> Failure {
    switch status {
    case errSecUserCanceled: return Failure("cancelled", Int(status))
    case errSecAuthFailed: return Failure("authentication_failed", Int(status))
    case errSecInteractionNotAllowed: return Failure("interaction_not_allowed", Int(status))
    case errSecDecode: return Failure("corrupt_data", Int(status))
    case errSecNotAvailable: return Failure("unavailable", Int(status))
    default: return Failure("storage_error", Int(status))
    }
}
private func live(_ op: Operation) -> Bool {
    if op.cancelled { return false }
    return DispatchQueue.main.sync { active === op && op.session == session && slot.pointee != 0 }
}
private func checkedString(_ request: [String: Any], _ key: String, _ max: Int) throws -> String {
    guard let v = request[key] as? String, !v.isEmpty, !v.contains("\0"), v.utf8.count <= max else { throw Failure("invalid_request") }
    return v
}

@_cdecl("DNBiometricStorageKitInitialize")
public func DNBiometricStorageKitInitialize(_ pointer: Int64, _ newSession: Int32) -> Int32 {
    guard Thread.isMainThread else { return 1 }
    typealias Register = @convention(c) (UnsafeMutablePointer<Int64>) -> Void
    guard let address = dlsym(dlopen(nil, RTLD_NOW), "DNRegisterAsyncDispatcherSlot") else { return 2 }
    if !registered { unsafeBitCast(address, to: Register.self)(slot); registered = true }
    let reset = slot.pointee == 0
    if newSession != 0 || reset { session &+= 1; active?.cancel(); active = nil }
    slot.pointee = pointer
    if backgroundObserver == nil {
        // didEnterBackground avoids cancelling merely because the system prompt
        // temporarily makes the application inactive.
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { _ in
                if let op = active { DNBiometricStorageKitCancel(op.id) }
            }
    }
    return reset && newSession == 0 ? 4 : 0
}
@_cdecl("DNBiometricStorageKitCancel")
public func DNBiometricStorageKitCancel(_ id: Int64) {
    guard Thread.isMainThread, let op = active, op.id == id else { return }
    op.cancel()
    // Completion is prompt; worker operations recheck cancellation before writes.
    // An operation already inside SecItemUpdate/Delete may have committed.
    active = nil
    send(id, error: Failure("cancelled"))
}
@_cdecl("DNBiometricStorageKitRequest")
public func DNBiometricStorageKitRequest(_ id: Int64, _ pointer: UnsafePointer<CChar>) -> Int32 {
    guard Thread.isMainThread, slot.pointee != 0 else { return 1 }
    let text = String(cString: pointer)
    guard text.utf8.count <= 524288 else { return 1 }
    let expected = session
    guard active == nil else {
        DispatchQueue.main.async {
            if expected == session { send(id, error: Failure("busy")) }
        }
        return 0
    }
    // Reserve before returning to Dart so immediate cancel/dispose owns this
    // request even before the deferred main-queue work starts.
    let op = Operation(id, session)
    active = op
    DispatchQueue.main.async {
        guard active === op, !op.cancelled, expected == session, slot.pointee != 0 else { return }
        do {
            guard let bytes = text.data(using: .utf8),
                  let request = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let command = request["operation"] as? String else { throw Failure("invalid_request") }
            if command == "availability" {
                var error: NSError?
                let possible = op.context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
                let codes = ["not_enrolled": "notEnrolled", "unavailable": "unavailable", "locked_out": "lockedOut", "passcode_not_set": "passcodeNotSet"]
                finish(op, value: possible ? "available" : codes[laFailure(error).code, default: "unknown"])
                return
            }
            let name = try checkedString(request, "name", 512)
            let namespace = try checkedString(request, "namespace", 128)
            let reason = try checkedString(request, "reason", 1024)
            _ = try checkedString(request, "title", 1024)
            let cancel = try checkedString(request, "cancelLabel", 1024)
            guard let reuse = request["reuseSeconds"] as? Double, reuse >= 0, reuse <= 300,
                  ["read", "readLegacy", "write", "delete"].contains(command) else { throw Failure("invalid_request") }
            if command == "readLegacy" && (name.contains("/") || name.contains("\\") || name == "." || name == "..") { throw Failure("invalid_request") }
            if command == "write" {
                guard let value = request["value"] as? String, value.utf8.count <= 65536 else { throw Failure("invalid_request") }
            }
            op.context.localizedReason = reason
            op.context.localizedFallbackTitle = ""
            op.context.localizedCancelTitle = cancel
            op.context.touchIDAuthenticationAllowableReuseDuration = reuse
            let work = {
                worker.async {
                    guard live(op) else { return }
                    do {
                        let service = command == "readLegacy" ? "flutter_biometric_storage" : "dev.dnplugins.biometric_storage_kit." + namespace
                        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: service, kSecAttrAccount as String: name,
                            kSecUseDataProtectionKeychain as String: true,
                            kSecUseAuthenticationContext as String: op.context]
                        switch command {
                        case "read", "readLegacy":
                            query[kSecReturnData as String] = true
                            query[kSecMatchLimit as String] = kSecMatchLimitOne
                            var result: CFTypeRef?
                            let status = SecItemCopyMatching(query as CFDictionary, &result)
                            if status == errSecItemNotFound { finish(op); return }
                            guard status == errSecSuccess else { throw statusFailure(status) }
                            guard let data = result as? Data, data.count <= 65536,
                                  let value = String(data: data, encoding: .utf8) else { throw Failure("corrupt_data") }
                            finish(op, value: value)
                        case "write":
                            var error: Unmanaged<CFError>?
                            guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                .biometryCurrentSet, &error) else { throw Failure("unavailable") }
                            let data = (request["value"] as! String).data(using: .utf8)!
                            var add = query
                            add[kSecAttrAccessControl as String] = access
                            add[kSecValueData as String] = data
                            guard live(op) else { return }
                            var status = SecItemAdd(add as CFDictionary, nil)
                            if status == errSecDuplicateItem {
                                guard live(op) else { return }
                                // Update data only: never destroy/recreate a protected item.
                                status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
                            }
                            guard status == errSecSuccess else { throw statusFailure(status) }
                            finish(op)
                        case "delete":
                            guard live(op) else { return }
                            let status = SecItemDelete(query as CFDictionary)
                            guard status == errSecSuccess || status == errSecItemNotFound else { throw statusFailure(status) }
                            finish(op)
                        default: throw Failure("invalid_request")
                        }
                    } catch let failure as Failure { finish(op, error: failure) }
                    catch { finish(op, error: Failure("storage_error")) }
                }
            }
            if command == "write" {
                // A fresh SecItemAdd need not prompt. Require biometric approval
                // explicitly for write; reads remain enforced by the Keychain ACL.
                op.context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                    if success { work() } else { finish(op, error: laFailure(error)) }
                }
            } else { work() }
        } catch let failure as Failure {
            if let op = active, op.id == id { active = nil; op.cancel() }
            send(id, error: failure)
        } catch {
            if let op = active, op.id == id { active = nil; op.cancel() }
            send(id, error: Failure("invalid_request"))
        }
    }
    return 0
}
