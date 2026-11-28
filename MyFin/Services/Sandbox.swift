import Foundation
import SwiftData

/// Runs automation messages against a throw-away copy of the user's cards, so the logic can be checked without
/// touching real data, notifications, the log or widgets.
enum Sandbox {
    nonisolated(unsafe) static var active = false

    struct Step {
        var source: TxSource
        var app: String
        var text: String
        var title: String = ""
    }

    struct Report {
        var steps: [(input: String, result: String)]
        var transactions: [String]
        var balances: [String]
    }

    /// One message per line: `[TBC UZ] text`, `[Uzum Bank | Payment completed] text` (app | notification title),
    /// `[SMS] text`, `[Apple Pay] amount | merchant | card`.
    static func parse(_ script: String) -> [Step] {
        script.components(separatedBy: .newlines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            var app = ""
            var title = ""
            var text = line
            if line.hasPrefix("["), let end = line.firstIndex(of: "]") {
                let head = String(line[line.index(after: line.startIndex)..<end])
                let parts = head.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                app = parts[0]
                title = parts.count > 1 ? parts[1] : ""
                text = String(line[line.index(after: end)...]).trimmingCharacters(in: .whitespaces)
            }
            let low = app.lowercased()
            let source: TxSource = low == "sms" ? .sms : low == "apple pay" ? .applePay
                : low == "skrinshot" ? .screenshot : .notification
            return Step(source: source, app: app, text: text, title: title)
        }
    }

    @MainActor
    static func run(_ steps: [Step], copying real: ModelContext) -> Report {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: DataStore.schema, configurations: [config]) else {
            return Report(steps: [], transactions: ["Sinov bazasini yaratib bo'lmadi"], balances: [])
        }
        let ctx = container.mainContext
        let realAccounts = FinanceEngine.accounts(real)
        for a in realAccounts {
            let c = Account(name: a.name, kind: a.kind, bank: a.bank, cardLast4: a.cardLast4, currency: a.currency,
                            balance: a.balance, colorHex: a.colorHex, sortOrder: a.sortOrder)
            c.id = a.id
            c.isArchived = a.isArchived
            ctx.insert(c)
        }
        for cat in FinanceEngine.categories(real) {
            ctx.insert(FinCategory(name: cat.name, icon: cat.icon, colorHex: cat.colorHex, kind: cat.kind,
                                   keywords: cat.keywords, sortOrder: cat.sortOrder, isSystem: cat.isSystem))
        }
        try? ctx.save()
        let before = Dictionary(uniqueKeysWithValues: realAccounts.map { ($0.id, $0.balance) })

        active = true
        defer { active = false }
        var results: [(String, String)] = []
        for s in steps {
            let r: String
            switch s.source {
            case .sms:
                r = FinanceEngine.processSMS(s.text, ctx: ctx)
            case .applePay:
                let parts = s.text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                r = FinanceEngine.processApplePay(amountText: parts.first ?? "", merchant: parts.count > 1 ? parts[1] : "",
                                                  card: parts.count > 2 ? parts[2] : "", ctx: ctx)
            case .screenshot:
                r = FinanceEngine.processScreenshotText(s.text, ctx: ctx)
            default:
                r = FinanceEngine.processNotification(title: s.title.isEmpty ? s.app : s.title, body: s.text, app: s.app, ctx: ctx)
            }
            results.append(("[\(s.app.isEmpty ? s.source.title : s.app)] \(s.text)", r))
        }

        let accs = FinanceEngine.accounts(ctx)
        func name(_ id: UUID?) -> String { accs.first { $0.id == id }?.displayName ?? "—" }
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let txLines = txs.map { t -> String in
            let mark = t.provisional ? "⏱ tasdiqlanmagan" : "✓"
            switch t.kind {
            case .transfer:
                return "O'tkazma \(Money.format(t.amount, t.currency)): \(name(t.accountID)) → \(name(t.toAccountID)) \(mark)"
            default:
                let signed = t.kind == .income ? t.amount : -t.amount
                return "\(t.title) \(Money.format(signed, t.currency, signed: true)) · \(name(t.accountID)) \(mark)"
            }
        }
        let balLines = accs.compactMap { a -> String? in
            guard let old = before[a.id] else { return "\(a.displayName): yangi karta, \(Money.format(a.balance, a.currency))" }
            guard abs(old - a.balance) >= 0.01 else { return nil }
            return "\(a.displayName): \(Money.format(old, a.currency)) → \(Money.format(a.balance, a.currency))"
        }
        return Report(steps: results, transactions: txLines, balances: balLines)
    }
}
