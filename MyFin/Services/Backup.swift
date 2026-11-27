import Foundation
import SwiftData

struct BackupFile: Codable {
    var version: Int = 1
    var createdAt: Date = Date()
    var accounts: [AccountDTO]
    var transactions: [TransactionDTO]
    var categories: [CategoryDTO]
    var debts: [DebtDTO]
    var payments: [PaymentDTO]
    var budgets: [BudgetDTO]
    var goals: [GoalDTO]
    var recurring: [RecurringDTO]
}

struct AccountDTO: Codable {
    var id: UUID; var name: String; var kind: String; var bank: String; var last4: String
    var currency: String; var balance: Double; var color: String; var includeInTotal: Bool
    var archived: Bool; var sortOrder: Int; var createdAt: Date
}

struct TransactionDTO: Codable {
    var id: UUID; var kind: String; var amount: Double; var currency: String; var accountID: UUID?
    var toAccountID: UUID?; var toAmount: Double; var category: String; var merchant: String
    var note: String; var date: Date; var source: String; var rawText: String; var applied: Bool
}

struct CategoryDTO: Codable {
    var id: UUID; var name: String; var icon: String; var color: String; var kind: String
    var keywords: String; var sortOrder: Int; var isSystem: Bool
}

struct DebtDTO: Codable {
    var id: UUID; var person: String; var phone: String; var direction: String; var principal: Double
    var remaining: Double; var currency: String; var dueDate: Date?; var note: String; var createdAt: Date
    var isClosed: Bool; var reminder: Bool
}

struct PaymentDTO: Codable {
    var id: UUID; var debtID: UUID; var amount: Double; var date: Date; var accountID: UUID?; var note: String
}

struct BudgetDTO: Codable {
    var id: UUID; var category: String; var limit: Double; var createdAt: Date
}

struct GoalDTO: Codable {
    var id: UUID; var name: String; var icon: String; var color: String; var target: Double
    var saved: Double; var currency: String; var deadline: Date?; var createdAt: Date
}

struct RecurringDTO: Codable {
    var id: UUID; var name: String; var amount: Double; var currency: String; var accountID: UUID?
    var category: String; var day: Int; var active: Bool; var lastPaid: String; var reminder: Bool; var createdAt: Date
}

@MainActor
enum BackupManager {
    static func fetchAll<T: PersistentModel>(_ type: T.Type, _ ctx: ModelContext) -> [T] {
        (try? ctx.fetch(FetchDescriptor<T>())) ?? []
    }

    static func makeBackup(_ ctx: ModelContext) -> BackupFile {
        let accounts: [AccountDTO] = fetchAll(Account.self, ctx).map { a in
            AccountDTO(id: a.id, name: a.name, kind: a.kindRaw, bank: a.bank, last4: a.cardLast4,
                       currency: a.currency, balance: a.balance, color: a.colorHex,
                       includeInTotal: a.includeInTotal, archived: a.isArchived,
                       sortOrder: a.sortOrder, createdAt: a.createdAt)
        }
        let transactions: [TransactionDTO] = fetchAll(FinTransaction.self, ctx).map { t in
            TransactionDTO(id: t.id, kind: t.kindRaw, amount: t.amount, currency: t.currency,
                           accountID: t.accountID, toAccountID: t.toAccountID, toAmount: t.toAmount,
                           category: t.categoryName, merchant: t.merchant, note: t.note, date: t.date,
                           source: t.sourceRaw, rawText: t.rawText, applied: t.balanceApplied)
        }
        let categories: [CategoryDTO] = fetchAll(FinCategory.self, ctx).map { c in
            CategoryDTO(id: c.id, name: c.name, icon: c.icon, color: c.colorHex, kind: c.kindRaw,
                        keywords: c.keywords, sortOrder: c.sortOrder, isSystem: c.isSystem)
        }
        let debts: [DebtDTO] = fetchAll(Debt.self, ctx).map { d in
            DebtDTO(id: d.id, person: d.person, phone: d.phone, direction: d.directionRaw,
                    principal: d.principal, remaining: d.remaining, currency: d.currency,
                    dueDate: d.dueDate, note: d.note, createdAt: d.createdAt,
                    isClosed: d.isClosed, reminder: d.reminder)
        }
        let payments: [PaymentDTO] = fetchAll(DebtPayment.self, ctx).map { p in
            PaymentDTO(id: p.id, debtID: p.debtID, amount: p.amount, date: p.date, accountID: p.accountID, note: p.note)
        }
        let budgets: [BudgetDTO] = fetchAll(Budget.self, ctx).map { b in
            BudgetDTO(id: b.id, category: b.categoryName, limit: b.limit, createdAt: b.createdAt)
        }
        let goals: [GoalDTO] = fetchAll(Goal.self, ctx).map { g in
            GoalDTO(id: g.id, name: g.name, icon: g.icon, color: g.colorHex, target: g.target,
                    saved: g.saved, currency: g.currency, deadline: g.deadline, createdAt: g.createdAt)
        }
        let recurring: [RecurringDTO] = fetchAll(RecurringPayment.self, ctx).map { r in
            RecurringDTO(id: r.id, name: r.name, amount: r.amount, currency: r.currency,
                         accountID: r.accountID, category: r.categoryName, day: r.dayOfMonth,
                         active: r.isActive, lastPaid: r.lastPaidMonth, reminder: r.reminder,
                         createdAt: r.createdAt)
        }
        return BackupFile(accounts: accounts, transactions: transactions, categories: categories, debts: debts,
                          payments: payments, budgets: budgets, goals: goals, recurring: recurring)
    }

    static func exportJSON(_ ctx: ModelContext) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(makeBackup(ctx))
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MyFin-zaxira-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func wipe(_ ctx: ModelContext) {
        fetchAll(Account.self, ctx).forEach { ctx.delete($0) }
        fetchAll(FinTransaction.self, ctx).forEach { ctx.delete($0) }
        fetchAll(FinCategory.self, ctx).forEach { ctx.delete($0) }
        fetchAll(Debt.self, ctx).forEach { ctx.delete($0) }
        fetchAll(DebtPayment.self, ctx).forEach { ctx.delete($0) }
        fetchAll(Budget.self, ctx).forEach { ctx.delete($0) }
        fetchAll(Goal.self, ctx).forEach { ctx.delete($0) }
        fetchAll(RecurringPayment.self, ctx).forEach { ctx.delete($0) }
        try? ctx.save()
    }

    static func importJSON(from url: URL, ctx: ModelContext) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let b = try decoder.decode(BackupFile.self, from: data)
        wipe(ctx)
        for a in b.accounts {
            let m = Account(name: a.name, kind: AccountKind(rawValue: a.kind) ?? .card, bank: a.bank, cardLast4: a.last4,
                            currency: a.currency, balance: a.balance, colorHex: a.color, sortOrder: a.sortOrder)
            m.id = a.id; m.includeInTotal = a.includeInTotal; m.isArchived = a.archived; m.createdAt = a.createdAt
            ctx.insert(m)
        }
        for t in b.transactions {
            let m = FinTransaction(kind: TxKind(rawValue: t.kind) ?? .expense, amount: t.amount, currency: t.currency,
                                   accountID: t.accountID, toAccountID: t.toAccountID, toAmount: t.toAmount,
                                   categoryName: t.category, merchant: t.merchant, note: t.note, date: t.date,
                                   source: TxSource(rawValue: t.source) ?? .manual, rawText: t.rawText)
            m.id = t.id; m.balanceApplied = t.applied
            ctx.insert(m)
        }
        for c in b.categories {
            let m = FinCategory(name: c.name, icon: c.icon, colorHex: c.color, kind: TxKind(rawValue: c.kind) ?? .expense,
                                keywords: c.keywords, sortOrder: c.sortOrder, isSystem: c.isSystem)
            m.id = c.id
            ctx.insert(m)
        }
        for d in b.debts {
            let m = Debt(person: d.person, direction: DebtDirection(rawValue: d.direction) ?? .iOwe, principal: d.principal,
                         currency: d.currency, dueDate: d.dueDate, note: d.note, phone: d.phone)
            m.id = d.id; m.remaining = d.remaining; m.createdAt = d.createdAt; m.isClosed = d.isClosed; m.reminder = d.reminder
            ctx.insert(m)
        }
        for p in b.payments {
            let m = DebtPayment(debtID: p.debtID, amount: p.amount, date: p.date, accountID: p.accountID, note: p.note)
            m.id = p.id
            ctx.insert(m)
        }
        for x in b.budgets {
            let m = Budget(categoryName: x.category, limit: x.limit)
            m.id = x.id; m.createdAt = x.createdAt
            ctx.insert(m)
        }
        for g in b.goals {
            let m = Goal(name: g.name, icon: g.icon, colorHex: g.color, target: g.target, currency: g.currency, deadline: g.deadline)
            m.id = g.id; m.saved = g.saved; m.createdAt = g.createdAt
            ctx.insert(m)
        }
        for r in b.recurring {
            let m = RecurringPayment(name: r.name, amount: r.amount, currency: r.currency, accountID: r.accountID,
                                     categoryName: r.category, dayOfMonth: r.day)
            m.id = r.id; m.isActive = r.active; m.lastPaidMonth = r.lastPaid; m.reminder = r.reminder; m.createdAt = r.createdAt
            ctx.insert(m)
        }
        try ctx.save()
        if b.categories.isEmpty { SeedData.seedIfNeeded(ctx) }
        return b.transactions.count
    }

    static func exportCSV(_ ctx: ModelContext) throws -> URL {
        let accounts = Dictionary(fetchAll(Account.self, ctx).map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let txs = fetchAll(FinTransaction.self, ctx).sorted { $0.date > $1.date }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var out = "Sana,Turi,Summa,Valyuta,Hisob,Qayerga,Kategoriya,Do'kon,Izoh,Manba\n"
        for t in txs {
            let from = t.accountID.flatMap { accounts[$0] } ?? ""
            let to = t.toAccountID.flatMap { accounts[$0] } ?? ""
            let row = [df.string(from: t.date), t.kind.title, String(format: "%.2f", t.amount), t.currency,
                       from, to, t.categoryName, t.merchant, t.note, t.source.title].map(esc).joined(separator: ",")
            out += row + "\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MyFin-operatsiyalar.csv")
        try Data(("\u{FEFF}" + out).utf8).write(to: url, options: .atomic)
        return url
    }
}
