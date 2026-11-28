import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = AccountKind.card.rawValue
    var bank: String = ""
    var cardLast4: String = ""
    var currency: String = "UZS"
    var balance: Double = 0
    var colorHex: String = "#4F7CFF"
    var includeInTotal: Bool = true
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(name: String, kind: AccountKind, bank: String = "", cardLast4: String = "",
         currency: String = "UZS", balance: Double = 0, colorHex: String = "#4F7CFF", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.bank = bank
        self.cardLast4 = cardLast4
        self.currency = currency
        self.balance = balance
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .card }
        set { kindRaw = newValue.rawValue }
    }

    var displayName: String {
        cardLast4.isEmpty ? name : "\(name) •\(cardLast4)"
    }
}

@Model
final class FinTransaction {
    var id: UUID = UUID()
    var kindRaw: String = TxKind.expense.rawValue
    var amount: Double = 0
    var currency: String = "UZS"
    var accountID: UUID? = nil
    var toAccountID: UUID? = nil
    var toAmount: Double = 0
    var categoryName: String = ""
    var merchant: String = ""
    var note: String = ""
    var date: Date = Date()
    var sourceRaw: String = TxSource.manual.rawValue
    var rawText: String = ""
    var balanceApplied: Bool = true
    var needsReview: Bool = false
    /// Reported only by a payment app / Wallet / a message without card number; the bank has not confirmed it yet.
    var provisional: Bool = false

    init(kind: TxKind, amount: Double, currency: String, accountID: UUID?, toAccountID: UUID? = nil,
         toAmount: Double = 0, categoryName: String = "", merchant: String = "", note: String = "",
         date: Date = Date(), source: TxSource = .manual, rawText: String = "") {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.currency = currency
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.toAmount = toAmount
        self.categoryName = categoryName
        self.merchant = merchant
        self.note = note
        self.date = date
        self.sourceRaw = source.rawValue
        self.rawText = rawText
    }

    var kind: TxKind {
        get { TxKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var source: TxSource {
        get { TxSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    /// Real income / spending. Transfers, debt principal and money set aside for goals only move money between
    /// the owner's own pots, so they stay out of income, expense, category and limit totals.
    var countsAsIncome: Bool { kind == .income && source != .debt && source != .goal }
    var countsAsExpense: Bool { kind == .expense && source != .debt && source != .goal }

    var title: String {
        if !merchant.isEmpty { return merchant }
        if kind == .transfer { return "O'tkazma" }
        return categoryName.isEmpty ? kind.title : categoryName
    }
}

@Model
final class FinCategory {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "tag.fill"
    var colorHex: String = "#94A3B8"
    var kindRaw: String = TxKind.expense.rawValue
    var keywords: String = ""
    var sortOrder: Int = 0
    var isSystem: Bool = false

    init(name: String, icon: String, colorHex: String, kind: TxKind, keywords: String = "",
         sortOrder: Int = 0, isSystem: Bool = false) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.keywords = keywords
        self.sortOrder = sortOrder
        self.isSystem = isSystem
    }

    var kind: TxKind {
        get { TxKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var keywordList: [String] {
        keywords.lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

@Model
final class Debt {
    var id: UUID = UUID()
    var person: String = ""
    var phone: String = ""
    var directionRaw: String = DebtDirection.iOwe.rawValue
    var principal: Double = 0
    var remaining: Double = 0
    var currency: String = "UZS"
    var dueDate: Date? = nil
    var note: String = ""
    var createdAt: Date = Date()
    var isClosed: Bool = false
    var reminder: Bool = true

    init(person: String, direction: DebtDirection, principal: Double, currency: String = "UZS",
         dueDate: Date? = nil, note: String = "", phone: String = "") {
        self.id = UUID()
        self.person = person
        self.phone = phone
        self.directionRaw = direction.rawValue
        self.principal = principal
        self.remaining = principal
        self.currency = currency
        self.dueDate = dueDate
        self.note = note
        self.createdAt = Date()
    }

    var direction: DebtDirection {
        get { DebtDirection(rawValue: directionRaw) ?? .iOwe }
        set { directionRaw = newValue.rawValue }
    }

    var paidFraction: Double {
        guard principal > 0 else { return 0 }
        return min(1, max(0, (principal - remaining) / principal))
    }

    var isOverdue: Bool {
        guard let dueDate, !isClosed else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }
}

@Model
final class DebtPayment {
    var id: UUID = UUID()
    var debtID: UUID = UUID()
    var amount: Double = 0
    var date: Date = Date()
    var accountID: UUID? = nil
    var note: String = ""

    init(debtID: UUID, amount: Double, date: Date = Date(), accountID: UUID? = nil, note: String = "") {
        self.id = UUID()
        self.debtID = debtID
        self.amount = amount
        self.date = date
        self.accountID = accountID
        self.note = note
    }
}

enum BudgetPeriod: String, CaseIterable, Identifiable {
    case month, week

    var id: String { rawValue }
    var title: String { self == .month ? "Oylik" : "Haftalik" }

    func interval(containing date: Date = Date()) -> DateInterval {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = .current
        let component: Calendar.Component = self == .month ? .month : .weekOfYear
        return cal.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 86_400)
    }

    func key(_ date: Date = Date()) -> String {
        let start = interval(containing: date).start
        let c = Calendar.current.dateComponents([.year, .month, .day], from: start)
        return "\(rawValue)-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

@Model
final class Budget {
    var id: UUID = UUID()
    var categoryName: String = ""
    var limit: Double = 0
    var periodRaw: String = BudgetPeriod.month.rawValue
    var createdAt: Date = Date()

    init(categoryName: String, limit: Double, period: BudgetPeriod = .month) {
        self.id = UUID()
        self.categoryName = categoryName
        self.limit = limit
        self.periodRaw = period.rawValue
        self.createdAt = Date()
    }

    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRaw) ?? .month }
        set { periodRaw = newValue.rawValue }
    }

    var isOverall: Bool { categoryName.isEmpty }
    var displayName: String { isOverall ? "Barcha xarajatlar" : categoryName }
}

@Model
final class Goal {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "target"
    var colorHex: String = "#8B5CF6"
    var target: Double = 0
    var saved: Double = 0
    var currency: String = "UZS"
    var deadline: Date? = nil
    var createdAt: Date = Date()

    init(name: String, icon: String, colorHex: String, target: Double, currency: String = "UZS", deadline: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.target = target
        self.currency = currency
        self.deadline = deadline
        self.createdAt = Date()
    }

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, saved / target)
    }

    var isCompleted: Bool { saved >= target && target > 0 }
}

@Model
final class RecurringPayment {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Double = 0
    var currency: String = "UZS"
    var accountID: UUID? = nil
    var categoryName: String = ""
    var dayOfMonth: Int = 1
    var isActive: Bool = true
    var lastPaidMonth: String = ""
    var reminder: Bool = true
    var createdAt: Date = Date()

    init(name: String, amount: Double, currency: String = "UZS", accountID: UUID? = nil,
         categoryName: String = "", dayOfMonth: Int = 1) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.currency = currency
        self.accountID = accountID
        self.categoryName = categoryName
        self.dayOfMonth = dayOfMonth
        self.createdAt = Date()
    }

    static func monthKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    var isPaidThisMonth: Bool { lastPaidMonth == RecurringPayment.monthKey() }

    var nextDate: Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month], from: now)
        let range = cal.range(of: .day, in: .month, for: now) ?? 1..<29
        comps.day = min(dayOfMonth, range.count)
        let thisMonth = cal.date(from: comps) ?? now
        if isPaidThisMonth {
            let next = cal.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth
            var nc = cal.dateComponents([.year, .month], from: next)
            let nr = cal.range(of: .day, in: .month, for: next) ?? 1..<29
            nc.day = min(dayOfMonth, nr.count)
            return cal.date(from: nc) ?? next
        }
        return thisMonth
    }
}

@Model
final class VaultItem {
    var id: UUID = UUID()
    var kindRaw: String = "custom"
    @Attribute(.externalStorage) var payload: Data = Data()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0

    init(kind: String, payload: Data, sortOrder: Int = 0) {
        self.id = UUID()
        self.kindRaw = kind
        self.payload = payload
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sortOrder = sortOrder
    }
}
