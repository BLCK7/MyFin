import Foundation
import SwiftData
import UserNotifications

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

    static func spent(budget: Budget, transactions: [FinTransaction], rates: RateStore, base: String) -> Double {
        let range = budget.period.interval()
        return transactions
            .filter { $0.kind == .expense && range.contains($0.date) && (budget.isOverall || $0.categoryName == budget.categoryName) }
            .reduce(0) { $0 + rates.convert($1.amount, from: $1.currency, to: base) }
    }

    /// How much can still be spent per day until the period ends without crossing the limit.
    static func safeDaily(budget: Budget, spent: Double) -> Double {
        let range = budget.period.interval()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = max(1, (cal.dateComponents([.day], from: today, to: range.end).day ?? 1))
        return max(0, budget.limit - spent) / Double(days)
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
        WidgetSync.schedule(ctx)
        return tx
    }

    static func delete(_ tx: FinTransaction, ctx: ModelContext) {
        if tx.balanceApplied { applyEffect(of: tx, sign: -1, ctx: ctx) }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["review-\(tx.id.uuidString)"])
        ctx.delete(tx)
        try? ctx.save()
        WidgetSync.schedule(ctx)
    }

    static func setBalance(_ account: Account, to value: Double, ctx: ModelContext) {
        account.balance = value
        try? ctx.save()
        WidgetSync.schedule(ctx)
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
        let budgets = (try? ctx.fetch(FetchDescriptor<Budget>())) ?? []
        let relevant = budgets.filter { $0.limit > 0 && ($0.isOverall || (!category.isEmpty && $0.categoryName == category)) }
        guard !relevant.isEmpty else { return }
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>())) ?? []
        let base = UserDefaults.standard.string(forKey: "baseCurrency") ?? "UZS"
        for b in relevant {
            let used = spent(budget: b, transactions: txs, rates: RateStore.shared, base: base)
            let ratio = used / b.limit
            let key = "budgetAlert-\(b.id.uuidString)-\(b.period.key())"
            let level = ratio >= 1 ? 2 : (ratio >= 0.8 ? 1 : 0)
            let previous = UserDefaults.standard.integer(forKey: key)
            guard level > previous else { continue }
            UserDefaults.standard.set(level, forKey: key)
            let name = "\(b.period.title) limit · \(b.displayName)"
            let body = "\(Money.format(used, base)) / \(Money.format(b.limit, base))"
            if level == 2 {
                Notifier.notifyNow(title: "\(name) oshib ketdi", body: body)
            } else {
                Notifier.notifyNow(title: "\(name): 80% ishlatildi", body: body + ". Kuniga ~\(Money.format(safeDaily(budget: b, spent: used), base)) qoldi.")
            }
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
        var bestName: String? = nil
        var bestLen = 0
        var bestOrder = Int.max
        for c in categories(ctx) where c.kind == kind {
            for k in c.keywordList where lower.contains(k) {
                if k.count > bestLen || (k.count == bestLen && c.sortOrder < bestOrder) {
                    bestName = c.name
                    bestLen = k.count
                    bestOrder = c.sortOrder
                }
            }
        }
        return bestName ?? (kind == .income ? "Boshqa kirim" : "Boshqa xarajat")
    }

    static func topCategories(kind: TxKind, limit: Int, ctx: ModelContext) -> [String] {
        let since = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>())) ?? []
        var counts: [String: Int] = [:]
        for t in txs where t.kind == kind && t.date >= since && !t.categoryName.isEmpty {
            counts[t.categoryName, default: 0] += 1
        }
        let valid = Set(categories(ctx).filter { $0.kind == kind }.map(\.name))
        var result = counts.filter { valid.contains($0.key) }.sorted { $0.value > $1.value }.map(\.key)
        let defaults = kind == .income
            ? ["Maosh", "Kirim o'tkazma", "Qo'shimcha daromad", "Boshqa kirim"]
            : ["Oziq-ovqat", "Kafe va restoran", SeedData.personalCategory, "Transport"]
        for d in defaults where !result.contains(d) && valid.contains(d) { result.append(d) }
        return Array(result.prefix(limit))
    }

    /// Remembers the user's choice: the merchant (or phone number) becomes a keyword of the chosen category.
    static func learn(category: String, from tx: FinTransaction, ctx: ModelContext) {
        guard UserDefaults.standard.object(forKey: "learnCategories") as? Bool ?? true else { return }
        var keys: [String] = []
        if let phone = SMSParser.phoneCompact(in: tx.merchant + " " + tx.rawText) { keys.append(phone) }
        let m = tx.merchant.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if m.count >= 3 && m.count <= 40 && !m.hasPrefix("+998") { keys.append(m) }
        guard !keys.isEmpty else { return }
        for c in categories(ctx) where c.kind == tx.kind {
            var list = c.keywordList
            if c.name == category {
                for k in keys where !list.contains(k) { list.append(k) }
            } else {
                list.removeAll { keys.contains($0) }
            }
            let joined = list.joined(separator: ",")
            if joined != c.keywords.lowercased() { c.keywords = joined }
        }
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

    static let automationSources: Set<String> = [TxSource.sms.rawValue, TxSource.notification.rawValue,
                                                 TxSource.applePay.rawValue, TxSource.screenshot.rawValue]

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
        let result = processCore(text, source: source, hint: "", ctx: ctx)
        AutomationLog.add(source: source.title, app: "", input: text, result: result)
        return result
    }

    static func processNotification(title: String, body: String, app: String, ctx: ModelContext) -> String {
        let bodyTrim = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [title, bodyTrim].filter { !$0.isEmpty }.joined(separator: "\n")
        let hint = app + " " + title
        let result: String
        if SMSParser.parse(bodyTrim)?.amount != nil {
            result = processCore(bodyTrim, source: .notification, hint: hint, ctx: ctx)
        } else {
            result = processCore(combined, source: .notification, hint: hint, ctx: ctx)
        }
        AutomationLog.add(source: TxSource.notification.title, app: app, input: combined, result: result)
        return result
    }

    static func processScreenshotText(_ text: String, ctx: ModelContext) -> String {
        let result = processCore(text, source: .screenshot, hint: text, ctx: ctx)
        AutomationLog.add(source: TxSource.screenshot.title, app: "", input: text, result: result)
        return result
    }

    static let knownBanks: [(key: String, name: String)] = [
        ("tbc", "TBC Bank"), ("uzum", "Uzum Bank"), ("anor", "Anorbank"), ("payme", "Payme"), ("paynet", "Paynet"),
        ("kapital", "Kapitalbank"), ("hamkor", "Hamkorbank"), ("ipak", "Ipak Yo'li"), ("agrobank", "Agrobank"),
        ("xalq", "Xalq banki"), ("nbu", "NBU"), ("asaka", "Asakabank"), ("ipoteka", "Ipoteka bank"),
        ("trast", "Trastbank"), ("davr", "Davr bank"), ("infin", "InfinBANK"), ("orient", "Orient Finans"),
        ("aloqa", "Aloqabank"), ("turon", "Turonbank"), ("click", "Click"), ("octo", "Octobank"), ("smart", "Smartbank")
    ]

    static func knownBank(in text: String) -> (key: String, name: String)? {
        let low = text.lowercased()
        return knownBanks.first { low.contains($0.key) }
    }

    static let pairSeparator = "\n— — —\n"

    /// One payment often produces two bank notifications (e.g. TBC: “Pul yechish, karta *7758 … Balans …” and
    /// “Siz "UzMobile" uchun … to'lov qildingiz”). They are merged into one transaction when they arrive within
    /// 3 minutes with the same amount, unless both name a card (then they are two separate payments).
    static func findCompanion(amount: Double, currency: String, kind: TxKind, hasCard: Bool, source: TxSource,
                              bankKey: String?, ctx: ModelContext) -> FinTransaction? {
        let since = Date().addingTimeInterval(-3 * 60)
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        return txs.prefix(30).first { t in
            guard t.date >= since, t.kind == kind, automationSources.contains(t.sourceRaw),
                  !t.rawText.contains(pairSeparator), t.currency == currency, abs(t.amount - amount) < 0.01 else { return false }
            let tHasCard = SMSParser.last4(in: t.rawText) != nil
            if hasCard && tHasCard { return false }
            if !hasCard && !tHasCard && t.sourceRaw == source.rawValue { return false }
            if let key = bankKey, let a = account(t.accountID, in: ctx) {
                let label = (a.bank + " " + a.name).lowercased()
                if !label.contains(key), let other = knownBank(in: label), other.key != key { return false }
            }
            return true
        }
    }

    static func merge(_ t: FinTransaction, text: String, cardAccount: Account?, merchant: String, quality: Int,
                      ctx: ModelContext) {
        if let acc = cardAccount, t.accountID != acc.id {
            if t.balanceApplied { applyEffect(of: t, sign: -1, ctx: ctx) }
            t.accountID = acc.id
            if t.balanceApplied { applyEffect(of: t, sign: 1, ctx: ctx) }
        }
        let existingQuality = SMSParser.quoted(in: t.rawText) != nil ? 2 : (t.merchant.isEmpty ? 0 : 1)
        if quality > existingQuality && !merchant.isEmpty {
            t.merchant = merchant
            if t.needsReview {
                t.categoryName = guessCategory(text: merchant + " " + text + " " + t.rawText, kind: t.kind, ctx: ctx)
            }
        }
        t.rawText += pairSeparator + text
        try? ctx.save()
        WidgetSync.schedule(ctx)
    }

    private static func processCore(_ text: String, source: TxSource, hint: String, ctx: ModelContext) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = SMSParser.parse(trimmed) else {
            return "Matnda summa topilmadi, hech narsa yozilmadi."
        }
        if isDuplicate(trimmed, ctx: ctx) {
            return "Bu xabar allaqachon yozilgan."
        }

        let all = accounts(ctx).filter { !$0.isArchived }
        let bank = knownBank(in: hint) ?? knownBank(in: trimmed)
        let bankAccount: Account? = bank.flatMap { b in
            all.first { $0.bank.lowercased().contains(b.key) || $0.name.lowercased().contains(b.key) }
        }

        var account: Account? = nil
        var created = false
        if let last4 = p.last4 {
            account = all.first { $0.cardLast4 == last4 }
            if account == nil, let ba = bankAccount, ba.cardLast4.isEmpty {
                ba.cardLast4 = last4
                account = ba
            }
            if account == nil {
                let a = Account(name: bank?.name ?? "Karta", kind: .card, bank: bank?.name ?? "", cardLast4: last4,
                                currency: p.balanceCurrency ?? p.currency, balance: 0,
                                colorHex: Palette.swatches.randomElement() ?? "#4F7CFF", sortOrder: all.count)
                ctx.insert(a)
                account = a
                created = true
            }
        }
        if account == nil { account = bankAccount ?? defaultAutomationAccount(ctx) }
        guard let acc = account else {
            return "Hisob topilmadi. Avval MyFin'da karta qo'shing."
        }

        var lines: [String] = []
        if let amount = p.amount, amount > 0 {
            let kind: TxKind = p.isIncome ? .income : .expense
            let converted = RateStore.shared.convert(amount, from: p.currency, to: acc.currency)
            let quoted = SMSParser.quoted(in: trimmed)
            if let comp = findCompanion(amount: amount, currency: p.currency, kind: kind, hasCard: p.last4 != nil,
                                        source: source, bankKey: bank?.key, ctx: ctx) {
                merge(comp, text: trimmed, cardAccount: p.last4 != nil ? acc : nil,
                      merchant: quoted ?? p.merchant, quality: quoted != nil ? 2 : (p.merchant.isEmpty ? 0 : 1), ctx: ctx)
                lines.append("Bitta to'lov: ikkinchi bildirishnoma “\(comp.merchant.isEmpty ? comp.categoryName : comp.merchant)” operatsiyasiga qo'shildi.")
            } else if let dup = findCrossSourceDuplicate(amount: amount, kind: kind, accountID: acc.id, source: source, ctx: ctx)
                ?? findCrossSourceDuplicate(amount: converted, kind: kind, accountID: acc.id, source: source, ctx: ctx) {
                if dup.merchant.isEmpty && !p.merchant.isEmpty { dup.merchant = p.merchant }
                if dup.rawText.isEmpty { dup.rawText = trimmed }
                lines.append("Bu operatsiya boshqa manbadan allaqachon yozilgan (\(dup.source.title)).")
            } else {
                var merchant = p.merchant
                let phone = SMSParser.phoneCompact(in: trimmed)
                if let phone {
                    let pretty = SMSParser.prettyPhone(phone)
                    merchant = merchant.isEmpty ? pretty : "\(merchant) \(pretty)"
                }
                let category = guessCategory(text: merchant + " " + (phone ?? "") + " " + trimmed, kind: kind, ctx: ctx)
                let tx = addTransaction(kind: kind, amount: amount, currency: p.currency, accountID: acc.id,
                                        category: category, merchant: merchant, source: source, rawText: trimmed, ctx: ctx)
                tx.needsReview = true
                try? ctx.save()
                Notifier.postReview(tx, account: acc)
                let signed = p.isIncome ? amount : -amount
                let title = merchant.isEmpty ? category : merchant
                lines.append("\(title): \(Money.format(signed, p.currency, signed: true))")
            }
        }
        let bankMatches = bank.map { b in
            all.filter { $0.bank.lowercased().contains(b.key) || $0.name.lowercased().contains(b.key) }.count
        } ?? 0
        let balanceOwnerKnown = p.last4 != nil || bankMatches == 1
        if p.balance != nil && !balanceOwnerKnown {
            lines.append("Xabarda karta raqami yo'q — qoldiq qaysi kartaga tegishli ekani aniq emas, balans o'zgartirilmadi.")
        }
        if let balance = p.balance, balanceOwnerKnown {
            let balCur = p.balanceCurrency ?? acc.currency
            let bankBalance = RateStore.shared.convert(balance, from: balCur, to: acc.currency)
            let diff = bankBalance - acc.balance
            let tolerance = acc.currency == "UZS" ? 1.0 : 0.01
            let checkOn = UserDefaults.standard.object(forKey: "balanceCheck") as? Bool ?? true
            if checkOn && !created && balCur == acc.currency && abs(diff) >= tolerance {
                Notifier.postBalanceMismatch(account: acc, bank: bankBalance, local: acc.balance, diff: diff)
                lines.append("⚠️ Balans mos emas — bankda \(Money.format(bankBalance, acc.currency)), MyFin'da \(Money.format(acc.balance, acc.currency)), farq \(Money.format(diff, acc.currency, signed: true)).")
            }
            acc.balance = bankBalance
            lines.append("\(acc.displayName) balansi: \(Money.format(acc.balance, acc.currency))")
        } else {
            lines.append("\(acc.displayName): \(Money.format(acc.balance, acc.currency))")
        }
        if created { lines.append("Yangi karta qo'shildi (•\(acc.cardLast4)).") }
        try? ctx.save()
        WidgetSync.schedule(ctx)
        return lines.joined(separator: "\n")
    }

    static func processApplePay(amountText: String, merchant: String, card: String, ctx: ModelContext) -> String {
        let result = applePayCore(amountText: amountText, merchant: merchant, card: card, ctx: ctx)
        AutomationLog.add(source: TxSource.applePay.title, app: card, input: "\(amountText) · \(merchant)", result: result)
        return result
    }

    private static func applePayCore(amountText: String, merchant: String, card: String, ctx: ModelContext) -> String {
        guard let amount = SMSParser.parseNumber(amountText.filter { "0123456789., \u{00A0}\u{202F}".contains($0) }), amount > 0 else {
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
        if match == nil, let bank = knownBank(in: card) {
            match = all.first { $0.bank.lowercased().contains(bank.key) || $0.name.lowercased().contains(bank.key) }
        }
        if match == nil { match = defaultAutomationAccount(ctx) }
        guard let acc = match else { return "Hisob topilmadi." }
        if let comp = findCompanion(amount: amount, currency: currency, kind: .expense, hasCard: !last4.isEmpty,
                                    source: .applePay, bankKey: knownBank(in: card)?.key, ctx: ctx) {
            merge(comp, text: "Apple Pay: \(amountText) · \(merchant) · \(card)", cardAccount: nil,
                  merchant: merchant, quality: merchant.isEmpty ? 0 : 2, ctx: ctx)
            return "Bu xarid bank bildirishnomasidan allaqachon yozilgan, do'kon nomi qo'shildi."
        }
        if let dup = findCrossSourceDuplicate(amount: amount, kind: .expense, accountID: acc.id, source: .applePay, ctx: ctx) {
            if !merchant.isEmpty { dup.merchant = merchant }
            try? ctx.save()
            return "Bu xarid allaqachon yozilgan (\(dup.source.title))."
        }
        let category = guessCategory(text: merchant, kind: .expense, ctx: ctx)
        let tx = addTransaction(kind: .expense, amount: amount, currency: currency, accountID: acc.id, category: category,
                                merchant: merchant, note: "Apple Pay", source: .applePay, ctx: ctx)
        tx.needsReview = true
        try? ctx.save()
        Notifier.postReview(tx, account: acc)
        return "\(merchant.isEmpty ? category : merchant): \(Money.format(-amount, currency, signed: true))\n\(acc.displayName): \(Money.format(acc.balance, acc.currency))"
    }

    /// Records the gap between MyFin and the bank balance as a transaction (balance itself is already synced).
    @discardableResult
    static func recordBalanceDifference(accountID: UUID, diff: Double, ctx: ModelContext) -> FinTransaction? {
        guard let acc = account(accountID, in: ctx), abs(diff) > 0 else { return nil }
        let kind: TxKind = diff < 0 ? .expense : .income
        let tx = addTransaction(kind: kind, amount: abs(diff), currency: acc.currency, accountID: acc.id,
                                category: kind == .expense ? "Boshqa xarajat" : "Boshqa kirim",
                                merchant: "Hisobga olinmagan", note: "Bank balansi bilan farq",
                                rawText: "Balans farqi", applyToBalance: false, ctx: ctx)
        tx.needsReview = true
        try? ctx.save()
        Notifier.postReview(tx, account: acc)
        return tx
    }
}
