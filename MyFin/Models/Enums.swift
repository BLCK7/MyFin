import SwiftUI

enum AccountKind: String, CaseIterable, Identifiable {
    case card, cash, savings, wallet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .card: return "Bank kartasi"
        case .cash: return "Naqd pul"
        case .savings: return "Jamg'arma / omonat"
        case .wallet: return "Elektron hamyon"
        }
    }

    var icon: String {
        switch self {
        case .card: return "creditcard.fill"
        case .cash: return "banknote.fill"
        case .savings: return "building.columns.fill"
        case .wallet: return "wallet.pass.fill"
        }
    }
}

enum TxKind: String, CaseIterable, Identifiable {
    case expense, income, transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "Chiqim"
        case .income: return "Kirim"
        case .transfer: return "O'tkazma"
        }
    }

    var icon: String {
        switch self {
        case .expense: return "arrow.up.right"
        case .income: return "arrow.down.left"
        case .transfer: return "arrow.left.arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .expense: return Palette.expense
        case .income: return Palette.income
        case .transfer: return Palette.transfer
        }
    }
}

enum TxSource: String, CaseIterable {
    case manual, sms, notification, applePay, recurring, debt, goal, siri

    var title: String {
        switch self {
        case .manual: return "Qo'lda"
        case .sms: return "Bank SMS"
        case .notification: return "Bank ilovasi"
        case .applePay: return "Apple Pay"
        case .recurring: return "Doimiy to'lov"
        case .debt: return "Qarz"
        case .goal: return "Maqsad"
        case .siri: return "Siri / Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .manual: return "hand.tap.fill"
        case .sms: return "message.fill"
        case .notification: return "bell.badge.fill"
        case .applePay: return "apple.logo"
        case .recurring: return "repeat"
        case .debt: return "person.2.fill"
        case .goal: return "target"
        case .siri: return "waveform"
        }
    }
}

enum DebtDirection: String, CaseIterable, Identifiable {
    case iOwe, owedToMe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iOwe: return "Men qarzdorman"
        case .owedToMe: return "Menga qarzdor"
        }
    }

    var shortTitle: String {
        switch self {
        case .iOwe: return "Qarzlarim"
        case .owedToMe: return "Haqlarim"
        }
    }

    var color: Color {
        switch self {
        case .iOwe: return Palette.expense
        case .owedToMe: return Palette.income
        }
    }

    var icon: String {
        switch self {
        case .iOwe: return "arrow.up.forward.circle.fill"
        case .owedToMe: return "arrow.down.backward.circle.fill"
        }
    }
}

enum Currencies {
    static let all = ["UZS", "USD", "EUR", "RUB"]

    static func name(_ code: String) -> String {
        switch code {
        case "UZS": return "O'zbek so'mi"
        case "USD": return "AQSh dollari"
        case "EUR": return "Yevro"
        case "RUB": return "Rossiya rubli"
        default: return code
        }
    }

    static func flag(_ code: String) -> String {
        switch code {
        case "UZS": return "🇺🇿"
        case "USD": return "🇺🇸"
        case "EUR": return "🇪🇺"
        case "RUB": return "🇷🇺"
        default: return "💱"
        }
    }
}

enum AppTab: Hashable {
    case home, transactions, accounts, debts, more
}
