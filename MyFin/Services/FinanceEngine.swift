import Foundation
import SwiftData

struct FinanceSummary {
    var totalAssets: Double = 0
    var iOwe: Double = 0
    var owedToMe: Double = 0
    var monthIncome: Double = 0
    var monthExpense: Double = 0
    var netWorth: Double { totalAssets + owedToMe - iOwe }
    var monthNet: Double { monthIncome - monthExpense }
}

struct CategorySlice: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
    let colorHex: String
    let icon: String
}

@MainActor
enum FinanceEngine {
    // MARK: Lookup

    static func accounts(_ ctx: ModelContext) -> [Account] {
        (try? ctx.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    static func categories(_ ctx: ModelContext) -> [FinCategory] {
        (try? ctx.fetch(FetchDescriptor<FinCategory>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    static func account(_ id: UUID?, in ctx: ModelContext) -> Account? {
        guard let id else { return nil }
        return accounts(ctx).first { $0.id == id }
    }

    // MARK: Summary

    static func summary(accounts: [Account], transactions: [FinTransaction], debts: [Debt],
                        rates: RateStore, base: String, month: Date = Date()) -> FinanceSummary {
        var s = FinanceSummary()
        for a in accounts where a.includeInTotal && !a.isArchived {
            s.totalAssets += rates.convert(a.balance, from: a.currency, to: base)
        }
        for d in debts where !d.isClosed {
            let v = rates.convert(d.remaining, from: d.currency, to: base)
            if d.direction == .iOwe { s.iOwe += v } else { s.owedToMe += v }
        }
        let cal = Calendar.current
        for t in transactions where cal.isDate(t.date, equalTo: month, toGranularity: .month) {
            let v = rates.convert(t.amount, from: t.currency, to: base)
            switch t.kind {
            case .income: s.monthIncome += v
            case .expense: s.monthExpense += v
            case .transfer: break
            }
        }
        return s
    }

    static func spendingByCategory(transactions: [FinTransaction], categories: [FinCategory],
                                   rates: RateStore, base: String, month: Date) -> [CategorySlice] {
        let cal = Calendar.current
        var totals: [String: Double] = [:]
        for t in transactions where t.kind == .expense && cal.isDate(t.date, equalTo: month, toGranularity: .month) {
            let key = t.categoryName.isEmpty ? "Boshqa xarajat" : t.categoryName
            totals[key, default: 0] += rates.convert(t.amount, from: t.currency, to: base)
        }
        let byName = Dictionary(categories.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        return totals.map { name, amount in
            let c = byName[name]
            return CategorySlice(name: name, amount: amount, colorHex: c?.colorHex ?? "#94A3B8", icon: c?.icon ?? "tag.fill")
        }
        .sorted { $0.amount > $1.amount }
    }

    static func spent(category: String, transactions: [FinTransaction], rates: RateStore, base: String, month: Date = Date()) -> Double {
        let cal = Calendar.current
        return transactions
            .filter { $0.kind == .expense && $0.categoryName == category && cal.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + rates.convert($1.amount, from: $1.currency, to: base) }
    }

    // MARK: Balances

    static func applyEffect(of tx: FinTransaction, sign: Double, ctx: ModelContext) {
        switch tx.kind {
        case .expense:
            if let a = account(tx.accountID, in: ctx) {
                a.balance -= RateStore.shared.convert(tx.amount, from: tx.currency, to: a.currency) * sign
            }
        case .income:
            if let a = account(tx.accountID, in: ctx) {
                a.balance += RateStore.shared.convert(tx.amount, from: tx.currency, to: a.currency) * sign
            }
        case .transfer:
            if let from = account(tx.accountID, in: ctx) {
                from.balance -= RateStore.shared.convert(tx.amount, from: tx.currency, to: from.currency) * sign
            }
            if let to = account(tx.toAccountID, in: ctx) {
                let incoming = tx.toAmount > 0 ? tx.toAmount : RateStore.shared.convert(tx.amount, from: tx.currency, to: to.currency)
                to.balance += incoming * sign
            }
        }
    }

    @discardableResult
    static func addTransaction(kind: TxKind, amount: Double, currency: String, accountID: UUID?,
                               toAccountID: UUID? = nil, toAmount: Double = 0, category: String = "",
                               merchant: String = "", note: String = "", date: Date = Date(),
                               source: TxSource = .manual, rawText: String = "", applyToBalance: Bool = true,
                               ctx: ModelContext) -> FinTransaction {
        let tx = FinTransaction(kind: kind, amount: amount, currency: currency, accountID: accountID,
                                toAccountID: toAccountID, toAmount: toAmount, categoryName: category,
                                merchant: merchant, note: note, date: date, source: source, rawText: rawText)
        tx.balanceApplied = applyToBalance
        ctx.insert(tx)
        if applyToBalance { applyEffect(of: tx, sign: 1, ctx: ctx) }
        try? ctx.save()
        if kind == .expense { checkBudget(category: category, ctx: ctx) }
        return tx
    }

    static func delete(_ tx: FinTransaction, ctx: ModelContext) {
        if tx.balanceApplied { applyEffect(of: tx, sign: -1, ctx: ctx) }
        ctx.delete(tx)
        try? ctx.save()
    }

    static func setBalance(_ account: Account, to value: Double, ctx: ModelContext) {
        account.balance = value
        try? ctx.save()
    }

    static func deleteAccount(_ account: Account, ctx: ModelContext) {
        let id = account.id
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>())) ?? []
        for t in txs where t.accountID == id || t.toAccountID == id {
            ctx.delete(t)
        }
        ctx.delete(account)
        try? ctx.save()
    }

    // MARK: Budgets

    static func checkBudget(category: String, ctx: ModelContext) {
        guard !category.isEmpty else { return }
        let budgets = (try? ctx.fetch(FetchDescriptor<Budget>())) ?? []
        guard let b = budgets.first(where: { $0.categoryName == category }), b.limit > 0 else { return }
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>())) ?? []
        let base = UserDefaults.standard.string(forKey: "baseCurrency") ?? "UZS"
        let used = spent(category: category, transactions: txs, rates: RateStore.shared, base: base)
        let ratio = used / b.limit
        let key = "budgetAlert-\(category)-\(RecurringPayment.monthKey())"
        let level = ratio >= 1 ? 2 : (ratio >= 0.8 ? 1 : 0)
        let previous = UserDefaults.standard.integer(forKey: key)
        guard level > previous else { return }
        UserDefaults.standard.set(level, forKey: key)
        let body = "\(category): \(Money.format(used, base)) / \(Money.format(b.limit, base))"
        if level == 2 {
            Notifier.notifyNow(title: "Byudjet oshib ketdi", body: body)
        } else {
            Notifier.notifyNow(title: "Byudjet 80% ga yetdi", body: body)
        }
    }

    // MARK: Debts

    static func addDebt(person: String, direction: DebtDirection, amount: Double, currency: String,
                        dueDate: Date?, note: String, reminder: Bool, moveMoney: Bool, accountID: UUID?,
                        ctx: ModelContext) -> Debt {
        let debt = Debt(person: person, direction: direction, principal: amount, currency: currency, dueDate: dueDate, note: note)
        debt.reminder = reminder
        ctx.insert(debt)
        if moveMoney, let accountID {
            addTransaction(kind: direction == .iOwe ? .income : .expense, amount: amount, currency: currency,
                           accountID: accountID,
                           category: direction == .iOwe ? "Boshqa kirim" : SeedData.debtPaymentCategory,
                           merchant: person, note: direction == .iOwe ? "Qarz olindi" : "Qarz berildi",
                           source: .debt, ctx: ctx)
        }
        try? ctx.save()
        Notifier.scheduleDebt(id: debt.id, person: person, amountText: Money.format(amount, currency),
                              direction: direction, due: dueDate, enabled: reminder)
        return debt
    }

    static func addDebtPayment(_ debt: Debt, amount: Double, accountID: UUID?, note: String, date: Date = Date(), ctx: ModelContext) {
        ctx.insert(DebtPayment(debtID: debt.id, amount: amount, date: date, accountID: accountID, note: note))
        debt.remaining = max(0, debt.remaining - amount)
        if debt.remaining < 0.005 {
            debt.isClosed = true
            Notifier.cancel(["debt-\(debt.id.uuidString)-before", "debt-\(debt.id.uuidString)-day"])
        }
        if let accountID {
            addTransaction(kind: debt.direction == .iOwe ? .expense : .income, amount: amount, currency: debt.currency,
                           accountID: accountID,
                           category: debt.direction == .iOwe ? SeedData.debtPaymentCategory : SeedData.debtReturnCategory,
                           merchant: debt.person, note: note.isEmpty ? "Qarz to'lovi" : note, date: date,
                           source: .debt, ctx: ctx)
        }
        try? ctx.save()
    }

    static func deleteDebt(_ debt: Debt, ctx: ModelContext) {
        let id = debt.id
        let payments = (try? ctx.fetch(FetchDescriptor<DebtPayment>())) ?? []
        for p in payments where p.debtID == id { ctx.delete(p) }
        Notifier.cancel(["debt-\(id.uuidString)-before", "debt-\(id.uuidString)-day"])
        ctx.delete(debt)
        try? ctx.save()
    }

    // MARK: Goals & recurring

    static func contribute(to goal: Goal, amount: Double, accountID: UUID?, ctx: ModelContext) {
        goal.saved += amount
        if let accountID {
            addTransaction(kind: .expense, amount: amount, currency: goal.currency, accountID: accountID,
                           category: SeedData.goalCategory, merchant: goal.name, note: "Maqsadga jamg'arma",
                           source: .goal, ctx: ctx)
        }
        try? ctx.save()
        if goal.isCompleted {
            Notifier.notifyNow(title: "Maqsadga yetdingiz! 🎉", body: "\(goal.name) uchun \(Money.format(goal.target, goal.currency)) yig'ildi.")
        }
    }

    static func markPaid(_ r: RecurringPayment, ctx: ModelContext) {
        addTransaction(kind: .expense, amount: r.amount, currency: r.currency, accountID: r.accountID,
                       category: r.categoryName, merchant: r.name, note: "Doimiy to'lov",
                       source: .recurring, ctx: ctx)
        r.lastPaidMonth = RecurringPayment.monthKey()
        try? ctx.save()
    }

    // MARK: Auto-categorization

    static func guessCategory(text: String, kind: TxKind, ctx: ModelContext) -> String {
        let lower = text.lowercased()
        let cats = categories(ctx).filter { $0.kind == kind }
        for c in cats {
            for k in c.keywordList where lower.contains(k) {
                return c.name
            }
        }
        return kind == .income ? "Boshqa kirim" : "Boshqa xarajat"
    }

    // MARK: Automation (SMS / Apple Pay)

    static func defaultAutomationAccount(_ ctx: ModelContext) -> Account? {
        let all = accounts(ctx).filter { !$0.isArchived }
        if let idString = UserDefaults.standard.string(forKey: "defaultSMSAccountID"),
           let id = UUID(uuidString: idString),
           let a = all.first(where: { $0.id == id }) {
            return a
        }
        return all.first { $0.kind == .card } ?? all.first
    }

    static func isDuplicate(_ text: String, ctx: ModelContext) -> Bool {
        let since = Date().addingTimeInterval(-15 * 60)
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        return txs.prefix(50).contains { $0.date >= since && !$0.rawText.isEmpty && $0.rawText == text }
    }

    static let automationSources: Set<String> = [TxSource.sms.rawValue, TxSource.notification.rawValue, TxSource.applePay.rawValue]

    static func findCrossSourceDuplicate(amount: Double, kind: TxKind, accountID: UUID, source: TxSource,
                                         ctx: ModelContext) -> FinTransaction? {
        let since = Date().addingTimeInterval(-6 * 60)
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        return txs.prefix(40).first { t in
            t.date >= since && t.accountID == accountID && t.kind == kind
                && abs(t.amount - amount) < 0.01
                && automationSources.contains(t.sourceRaw) && t.sourceRaw != source.rawValue
        }
    }

    static func processSMS(_ text: String, source: TxSource = .sms, ctx: ModelContext) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = SMSParser.parse(trimmed) else {
            return "Matnda summa topilmadi, hech narsa yozilmadi."
        }
        if isDuplicate(trimmed, ctx: ctx) {
            return "Bu xabar allaqachon yozilgan."
        }

        var account: Account? = nil
        var created = false
        if let last4 = p.last4 {
            account = accounts(ctx).first { $0.cardLast4 == last4 }
            if account == nil {
                let a = Account(name: "Karta", kind: .card, cardLast4: last4, currency: p.balanceCurrency ?? p.currency,
                                balance: 0, colorHex: Palette.swatches.randomElement() ?? "#4F7CFF",
                                sortOrder: accounts(ctx).count)
                ctx.insert(a)
                account = a
                created = true
            }
        }
        if account == nil { account = defaultAutomationAccount(ctx) }
        guard let acc = account else {
            return "Hisob topilmadi. Avval MyFin'da karta qo'shing."
        }

        var lines: [String] = []
        if let amount = p.amount, amount > 0 {
            let kind: TxKind = p.isIncome ? .income : .expense
            let converted = RateStore.shared.convert(amount, from: p.currency, to: acc.currency)
            if let dup = findCrossSourceDuplicate(amount: amount, kind: kind, accountID: acc.id, source: source, ctx: ctx)
                ?? findCrossSourceDuplicate(amount: converted, kind: kind, accountID: acc.id, source: source, ctx: ctx) {
                if dup.merchant.isEmpty && !p.merchant.isEmpty { dup.merchant = p.merchant }
                if dup.rawText.isEmpty { dup.rawText = trimmed }
                lines.append("Bu operatsiya boshqa manbadan allaqachon yozilgan (\(dup.source.title)).")
            } else {
                let category = guessCategory(text: p.merchant + " " + trimmed, kind: kind, ctx: ctx)
                addTransaction(kind: kind, amount: amount, currency: p.currency, accountID: acc.id,
                               category: category, merchant: p.merchant, source: source, rawText: trimmed, ctx: ctx)
                let signed = p.isIncome ? amount : -amount
                let title = p.merchant.isEmpty ? category : p.merchant
                lines.append("\(title): \(Money.format(signed, p.currency, signed: true))")
            }
        }
        if let balance = p.balance {
            let balCur = p.balanceCurrency ?? acc.currency
            acc.balance = RateStore.shared.convert(balance, from: balCur, to: acc.currency)
            lines.append("\(acc.displayName) balansi: \(Money.format(acc.balance, acc.currency))")
        } else {
            lines.append("\(acc.displayName): \(Money.format(acc.balance, acc.currency))")
        }
        if created { lines.append("Yangi karta qo'shildi (•\(acc.cardLast4)).") }
        try? ctx.save()
        return lines.joined(separator: "\n")
    }

    static func processNotification(title: String, body: String, app: String, ctx: ModelContext) -> String {
        let bodyTrim = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if SMSParser.parse(bodyTrim) != nil {
            return processSMS(bodyTrim, source: .notification, ctx: ctx)
        }
        let combined = [title, bodyTrim].filter { !$0.isEmpty }.joined(separator: "\n")
        return processSMS(combined, source: .notification, ctx: ctx)
    }

    static func processApplePay(amountText: String, merchant: String, card: String, ctx: ModelContext) -> String {
        guard let amount = SMSParser.parseNumber(amountText.filter { "0123456789.,  ".contains($0) }), amount > 0 else {
            return "Summa noto'g'ri: \(amountText)"
        }
        let currency: String = {
            let up = amountText.uppercased()
            if up.contains("$") || up.contains("USD") { return "USD" }
            if up.contains("€") || up.contains("EUR") { return "EUR" }
            if up.contains("₽") || up.contains("RUB") { return "RUB" }
            return "UZS"
        }()
        let all = accounts(ctx).filter { !$0.isArchived }
        let digits = card.filter(\.isNumber)
        let last4 = digits.count >= 4 ? String(digits.suffix(4)) : ""
        let lowerCard = card.lowercased()
        var match: Account? = nil
        if !last4.isEmpty {
            match = all.first { $0.cardLast4 == last4 }
        }
        if match == nil && !lowerCard.isEmpty {
            match = all.first { a in
                let n = a.name.lowercased()
                let b = a.bank.lowercased()
                return (!n.isEmpty && lowerCard.contains(n)) || (!b.isEmpty && lowerCard.contains(b))
            }
        }
        if match == nil { match = defaultAutomationAccount(ctx) }
        guard let acc = match else { return "Hisob topilmadi." }
        if let dup = findCrossSourceDuplicate(amount: amount, kind: .expense, accountID: acc.id, source: .applePay, ctx: ctx) {
            if !merchant.isEmpty { dup.merchant = merchant }
            try? ctx.save()
            return "Bu xarid allaqachon yozilgan (\(dup.source.title))."
        }
        let category = guessCategory(text: merchant, kind: .expense, ctx: ctx)
        addTransaction(kind: .expense, amount: amount, currency: currency, accountID: acc.id, category: category,
                       merchant: merchant, note: "Apple Pay", source: .applePay, ctx: ctx)
        return "\(merchant.isEmpty ? category : merchant): \(Money.format(-amount, currency, signed: true))\n\(acc.displayName): \(Money.format(acc.balance, acc.currency))"
    }
}
