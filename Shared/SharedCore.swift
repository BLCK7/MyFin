import SwiftUI
import Foundation

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

enum Palette {
    static let accent = Color(hex: "#7C8CFF")
    static let income = Color(hex: "#34D399")
    static let expense = Color(hex: "#FB7185")
    static let transfer = Color(hex: "#60A5FA")
    static let warning = Color(hex: "#FBBF24")
    static let swatches = ["#4F7CFF", "#7C3AED", "#EC4899", "#F59E0B", "#10B981",
                           "#06B6D4", "#EF4444", "#64748B", "#0EA5E9", "#84CC16"]
}

enum Money {
    static func symbol(_ code: String) -> String {
        switch code {
        case "UZS": return "so'm"
        case "USD": return "$"
        case "EUR": return "€"
        case "RUB": return "₽"
        default: return code
        }
    }

    static func decimals(_ code: String) -> Int { code == "UZS" ? 0 : 2 }

    static func number(_ value: Double, decimals: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.decimalSeparator = ","
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = decimals
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "0"
    }

    static func format(_ value: Double, _ code: String, signed: Bool = false) -> String {
        let num = number(abs(value), decimals: decimals(code))
        var sign = value < 0 ? "−" : ""
        if signed && value > 0 { sign = "+" }
        switch code {
        case "USD", "EUR": return "\(sign)\(symbol(code))\(num)"
        default: return "\(sign)\(num) \(symbol(code))"
        }
    }

    static func compact(_ value: Double) -> String {
        let a = abs(value)
        let sign = value < 0 ? "−" : ""
        if a >= 1_000_000_000 { return sign + number(a / 1_000_000_000, decimals: 1) + " mlrd" }
        if a >= 1_000_000 { return sign + number(a / 1_000_000, decimals: 1) + " mln" }
        if a >= 1_000 { return sign + number(a / 1_000, decimals: 0) + " ming" }
        return sign + number(a, decimals: 0)
    }

    static func compactFormat(_ value: Double, _ code: String) -> String {
        if code == "UZS" { return compact(value) + " so'm" }
        return format(value, code)
    }
}

enum AppGroup {
    static let base = "group.uz.saminov.myfin"

    static let identifier: String = {
        let groups = signedAppGroups(Bundle.main)
        return groups.first { $0.hasPrefix(base) } ?? groups.first ?? base
    }()

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var snapshotURL: URL? { containerURL?.appendingPathComponent("widget-snapshot.json") }

    /// SideStore/AltStore append the signing team ID to app group identifiers,
    /// so the real identifier is read back from this binary's own code-signature entitlements.
    static func signedAppGroups(_ bundle: Bundle) -> [String] {
        guard let url = bundle.executableURL,
              let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return [] }
        let key = Data(("<key>" + "com.apple.security.application-groups" + "</key>").utf8)
        guard let keyRange = data.range(of: key, options: .backwards),
              let start = data.range(of: Data("<?xml".utf8), options: .backwards,
                                     in: data.startIndex..<keyRange.lowerBound)?.lowerBound,
              let end = data.range(of: Data("</plist>".utf8), options: [],
                                   in: keyRange.upperBound..<data.endIndex)?.upperBound,
              let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start..<end),
                                                                      options: [], format: nil) as? [String: Any]
        else { return [] }
        return plist["com.apple.security.application-groups"] as? [String] ?? []
    }
}

struct WidgetSnapshot: Codable {
    struct Acc: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var last4: String
        var balance: Double
        var currency: String
        var colorHex: String
        var icon: String
    }

    struct Tx: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var amount: Double
        var currency: String
        var isIncome: Bool
        var isTransfer: Bool
        var date: Date
        var icon: String
        var colorHex: String
    }

    var updatedAt: Date
    var base: String
    var hide: Bool
    var netWorth: Double
    var totalBalance: Double
    var todayExpense: Double
    var todayIncome: Double
    var monthIncome: Double
    var monthExpense: Double
    var budgetLimit: Double
    var pendingReview: Int
    var accounts: [Acc]
    var recent: [Tx]

    static let placeholder = WidgetSnapshot(
        updatedAt: Date(), base: "UZS", hide: false, netWorth: 18_450_000, totalBalance: 15_200_000,
        todayExpense: 186_000, todayIncome: 0, monthIncome: 9_500_000, monthExpense: 4_320_000,
        budgetLimit: 6_000_000, pendingReview: 2,
        accounts: [
            Acc(id: "1", name: "Asosiy karta", last4: "1234", balance: 8_700_000, currency: "UZS", colorHex: "#4F7CFF", icon: "creditcard.fill"),
            Acc(id: "2", name: "Naqd pul", last4: "", balance: 1_500_000, currency: "UZS", colorHex: "#10B981", icon: "banknote.fill"),
            Acc(id: "3", name: "Dollar", last4: "", balance: 400, currency: "USD", colorHex: "#0EA5E9", icon: "banknote.fill")
        ],
        recent: [
            Tx(id: "a", title: "Korzinka", amount: 86_000, currency: "UZS", isIncome: false, isTransfer: false, date: Date(), icon: "cart.fill", colorHex: "#22C55E"),
            Tx(id: "b", title: "Yandex Go", amount: 24_000, currency: "UZS", isIncome: false, isTransfer: false, date: Date(), icon: "car.fill", colorHex: "#3B82F6"),
            Tx(id: "c", title: "Maosh", amount: 9_500_000, currency: "UZS", isIncome: true, isTransfer: false, date: Date(), icon: "briefcase.fill", colorHex: "#10B981")
        ]
    )

    static func load() -> WidgetSnapshot? {
        guard let url = AppGroup.snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = AppGroup.snapshotURL else { return }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(self) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
