import Foundation
import Security
import CommonCrypto
import LocalAuthentication
import Observation
import UIKit

enum PasscodeStore {
    private static let service = "uz.saminov.myfin.passcode"
    private static let hashKey = "pinHash"
    private static let saltKey = "pinSalt"
    private static let failsKey = "pinFailures"
    private static let lockoutKey = "pinLockoutUntil"
    private static let iterations: UInt32 = 120_000

    enum VerifyResult {
        case success
        case failure(remaining: Int)
        case lockedOut(until: Date)
    }

    static var isSet: Bool { read(hashKey) != nil && read(saltKey) != nil }

    static var length: Int { UserDefaults.standard.integer(forKey: "pinLength") == 4 ? 4 : 6 }

    static var failures: Int { UserDefaults.standard.integer(forKey: failsKey) }

    static var lockoutUntil: Date? {
        guard let d = UserDefaults.standard.object(forKey: lockoutKey) as? Date, d > Date() else { return nil }
        return d
    }

    static func set(_ pin: String) {
        var salt = Data(count: 16)
        let ok = salt.withUnsafeMutableBytes { buf -> Bool in
            guard let base = buf.baseAddress else { return false }
            return SecRandomCopyBytes(kSecRandomDefault, 16, base) == errSecSuccess
        }
        if !ok { salt = Data(UUID().uuidString.utf8.prefix(16)) }
        guard let hash = derive(pin, salt: salt) else { return }
        write(salt, for: saltKey)
        write(hash, for: hashKey)
        UserDefaults.standard.set(pin.count, forKey: "pinLength")
        UserDefaults.standard.set(true, forKey: "pinSet")
        resetFailures()
    }

    static func verify(_ pin: String) -> VerifyResult {
        if let until = lockoutUntil { return .lockedOut(until: until) }
        guard let salt = read(saltKey), let stored = read(hashKey), let hash = derive(pin, salt: salt) else {
            return .failure(remaining: 0)
        }
        if constantTimeEqual(hash, stored) {
            resetFailures()
            return .success
        }
        let fails = failures + 1
        UserDefaults.standard.set(fails, forKey: failsKey)
        let delay = lockoutDelay(fails)
        if delay > 0 {
            let until = Date().addingTimeInterval(delay)
            UserDefaults.standard.set(until, forKey: lockoutKey)
            return .lockedOut(until: until)
        }
        return .failure(remaining: max(0, 5 - fails))
    }

    static func resetFailures() {
        UserDefaults.standard.removeObject(forKey: failsKey)
        UserDefaults.standard.removeObject(forKey: lockoutKey)
    }

    static func clear() {
        delete(hashKey)
        delete(saltKey)
        resetFailures()
        UserDefaults.standard.set(false, forKey: "pinSet")
    }

    private static func lockoutDelay(_ fails: Int) -> TimeInterval {
        switch fails {
        case ..<5: return 0
        case 5: return 30
        case 6: return 60
        case 7: return 300
        default: return 900
        }
    }

    private static func derive(_ pin: String, salt: Data) -> Data? {
        var out = [UInt8](repeating: 0, count: 32)
        let pinLength = pin.utf8.count
        let status: Int32 = salt.withUnsafeBytes { saltBuf in
            let saltPtr = saltBuf.bindMemory(to: UInt8.self).baseAddress
            return CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pin, pinLength, saltPtr, salt.count,
                                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &out, out.count)
        }
        return status == Int32(kCCSuccess) ? Data(out) : nil
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[a.startIndex + i] ^ b[b.startIndex + i] }
        return diff == 0
    }

    private static func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    private static func write(_ data: Data, for key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
        var q = baseQuery(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        if SecItemAdd(q as CFDictionary, nil) == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: "kcfallback.\(key)")
        } else {
            UserDefaults.standard.set(data, forKey: "kcfallback.\(key)")
        }
    }

    private static func read(_ key: String) -> Data? {
        var q = baseQuery(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let d = item as? Data {
            return d
        }
        return UserDefaults.standard.data(forKey: "kcfallback.\(key)")
    }

    private static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "kcfallback.\(key)")
    }
}

@Observable
@MainActor
final class AppLock {
    static let shared = AppLock()

    var isLocked = !UITestSupport.isActive
    private var backgroundedAt: Date?

    private init() {}

    var autoLockSeconds: Int {
        UserDefaults.standard.object(forKey: "autoLockSeconds") as? Int ?? 0
    }

    func didEnterBackground() {
        if backgroundedAt == nil { backgroundedAt = Date() }
    }

    func didBecomeActive() {
        guard let b = backgroundedAt else { return }
        backgroundedAt = nil
        if Date().timeIntervalSince(b) >= Double(autoLockSeconds) {
            isLocked = true
        }
    }

    func lock() { isLocked = true }
    func unlock() { isLocked = false }
}

enum Haptics {
    @MainActor static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    @MainActor static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    @MainActor static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    @MainActor static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}
