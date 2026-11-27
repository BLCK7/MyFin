import Foundation
import CryptoKit
import Security
import Observation
import UIKit
import UniformTypeIdentifiers

struct VaultField: Codable, Identifiable, Hashable {
    var id = UUID()
    var label: String
    var value: String
    var secret: Bool = true
    var keyboard: String = "text"
}

struct VaultPayload: Codable {
    var title: String
    var fields: [VaultField]
    var notes: String = ""
    var images: [Data] = []
    var expiry: Date? = nil
}

enum VaultKind: String, CaseIterable, Identifiable {
    case passport, idCard, bankCard, license, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passport: return "Pasport"
        case .idCard: return "ID karta"
        case .bankCard: return "Bank kartasi"
        case .license: return "Haydovchilik guvohnomasi"
        case .custom: return "Boshqa hujjat"
        }
    }

    var icon: String {
        switch self {
        case .passport: return "book.closed.fill"
        case .idCard: return "person.text.rectangle.fill"
        case .bankCard: return "creditcard.fill"
        case .license: return "car.fill"
        case .custom: return "doc.text.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .passport: return "#2563EB"
        case .idCard: return "#0EA5E9"
        case .bankCard: return "#7C3AED"
        case .license: return "#F59E0B"
        case .custom: return "#64748B"
        }
    }

    var template: [VaultField] {
        switch self {
        case .passport, .idCard:
            return [
                VaultField(label: "F.I.Sh.", value: "", secret: false),
                VaultField(label: "Seriya va raqam", value: ""),
                VaultField(label: "JShShIR (PINFL)", value: "", keyboard: "number"),
                VaultField(label: "Tug'ilgan sana", value: "", secret: false),
                VaultField(label: "Berilgan sana", value: "", secret: false),
                VaultField(label: "Amal qilish muddati", value: "", secret: false),
                VaultField(label: "Kim tomonidan berilgan", value: "", secret: false)
            ]
        case .bankCard:
            return [
                VaultField(label: "Karta egasi", value: "", secret: false),
                VaultField(label: "Karta raqami", value: "", keyboard: "number"),
                VaultField(label: "Amal qilish muddati (OO/YY)", value: "", secret: false),
                VaultField(label: "Bank", value: "", secret: false),
                VaultField(label: "To'lov tizimi", value: "", secret: false),
                VaultField(label: "Hisob raqami (IBAN)", value: "", keyboard: "number")
            ]
        case .license:
            return [
                VaultField(label: "F.I.Sh.", value: "", secret: false),
                VaultField(label: "Guvohnoma raqami", value: ""),
                VaultField(label: "Toifalar", value: "", secret: false),
                VaultField(label: "Berilgan sana", value: "", secret: false),
                VaultField(label: "Amal qilish muddati", value: "", secret: false)
            ]
        case .custom:
            return [VaultField(label: "Maydon", value: "")]
        }
    }
}

enum VaultCrypto {
    private static let service = "uz.saminov.myfin.vault"
    private static let account = "vault-key-v1"

    enum VaultError: Error { case keychain, sealing }

    static func key() throws -> SymmetricKey {
        if let data = readKey() { return SymmetricKey(data: data) }
        let k = SymmetricKey(size: .bits256)
        let data = k.withUnsafeBytes { Data($0) }
        guard storeKey(data) else { throw VaultError.keychain }
        return k
    }

    static func seal(_ payload: VaultPayload) throws -> Data {
        let json = try JSONEncoder().encode(payload)
        guard let combined = try AES.GCM.seal(json, using: try key()).combined else { throw VaultError.sealing }
        return combined
    }

    static func open(_ data: Data) throws -> VaultPayload {
        let box = try AES.GCM.SealedBox(combined: data)
        let json = try AES.GCM.open(box, using: try key())
        return try JSONDecoder().decode(VaultPayload.self, from: json)
    }

    static func destroyKey() {
        SecItemDelete(query() as CFDictionary)
    }

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func readKey() -> Data? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func storeKey(_ data: Data) -> Bool {
        var q = query()
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemDelete(query() as CFDictionary)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}

@Observable
@MainActor
final class VaultSession {
    static let shared = VaultSession()
    private(set) var unlockedUntil: Date?
    private init() {}

    var isUnlocked: Bool {
        guard let u = unlockedUntil else { return false }
        return u > Date()
    }

    func unlock() { unlockedUntil = Date().addingTimeInterval(180) }
    func touch() { if isUnlocked { unlockedUntil = Date().addingTimeInterval(180) } }
    func lock() { unlockedUntil = nil }
}

enum SecureClipboard {
    @MainActor
    static func copy(_ value: String, seconds: TimeInterval = 60) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: value]],
                                      options: [.expirationDate: Date().addingTimeInterval(seconds), .localOnly: true])
        Haptics.success()
    }
}

enum ImageTools {
    static func compress(_ data: Data, maxSide: CGFloat = 1600) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let size = img.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let out = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: target)) }
        return out.jpegData(compressionQuality: 0.8)
    }
}
