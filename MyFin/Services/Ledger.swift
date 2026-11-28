import Foundation
import SwiftData
import UserNotifications

/// One message from an automation (bank app notification, SMS, Apple Pay, screenshot), normalised.
struct BankEvent {
    var text: String
    var tag: String
    var source: TxSource
    var hint: String
    var amount: Double?
    var currency: String
    var kind: TxKind
    var last4: String?
    var balance: Double?
    var balanceCurrency: String?
    var merchant: String
    var merchantQuality: Int
    var cardName: String = ""

    var stored: String { "[\(tag)] \(text)" }
}

/// How MyFin keeps one payment = one transaction, whatever number of apps report it:
///
/// * Every card has one trusted source: the issuing bank's own app, or bank SMS. A message from it that names
///   the card (…7758) is **confirmed**.
/// * Everything else — Payme, Paynet, Click, Wallet / Apple Pay, another bank's app where the card is linked,
///   bank messages without a card number — is **unconfirmed**: it is recorded at once on the best-guess card,
///   and when the confirming message arrives (within 4 minutes, same amount, or bank amount ≤1.5% higher because
///   of a fee) both become one transaction on the right card with the bank's amount.
/// * The same app reporting the same amount twice means two payments; two different apps reporting it within the
///   window means one payment.
/// * An expense on one own card and an equal income on another within the window become a transfer.
/// * The balance in bank messages is the final check: a mismatch raises a notification that points at the
///   likely duplicate or misplaced transaction.
extension FinanceEngine {
    static let pairSeparator = "\n— — —\n"
    static let matchWindow: TimeInterval = 4 * 60
    static let aggregatorKeys: Set<String> = ["payme", "paynet", "click"]

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

    static func appTag(of raw: String) -> String {
        guard raw.hasPrefix("["), let end = raw.firstIndex(of: "]") else { return "" }
        return String(raw[raw.index(after: raw.startIndex)..<end]).lowercased()
    }

    static func chunkTags(_ raw: String) -> Set<String> {
        Set(raw.components(separatedBy: pairSeparator).map { appTag(of: $0) }.filter { !$0.isEmpty })
    }

    static func issuerKey(of account: Account) -> String? {
        guard let b = knownBank(in: account.bank + " " + account.name), !aggregatorKeys.contains(b.key) else { return nil }
        return b.key
    }

    static func senderKey(_ e: BankEvent) -> String? {
        if e.source == .applePay { return nil }
        return knownBank(in: e.tag + " " + e.hint)?.key
    }

    // MARK: Entry points

    static func processSMS(_ text: String, source: TxSource = .sms, ctx: ModelContext) -> String {
        let tag = source == .sms ? "SMS" : source.title
        let result = ingest(text: text, tag: tag, source: source, hint: "", ctx: ctx)
        AutomationLog.add(source: source.title, app: "", input: text, result: result)
        return result
    }

    static func processNotification(title: String, body: String, app: String, ctx: ModelContext) -> String {
        let bodyTrim = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [title, bodyTrim].filter { !$0.isEmpty }.joined(separator: "\n")
        let appName = app.trimmingCharacters(in: .whitespaces)
        let tag = appName.isEmpty ? (title.isEmpty ? "Bildirishnoma" : title) : appName
        let text = SMSParser.parse(bodyTrim)?.amount != nil ? bodyTrim : combined
        let result = ingest(text: text, tag: tag, source: .notification, hint: appName + " " + title, ctx: ctx)
        AutomationLog.add(source: TxSource.notification.title, app: appName, input: combined, result: result)
        return result
    }

    static func processScreenshotText(_ text: String, ctx: ModelContext) -> String {
        let result = ingest(text: text, tag: "Skrinshot", source: .screenshot, hint: text, ctx: ctx)
        AutomationLog.add(source: TxSource.screenshot.title, app: "", input: text, result: result)
        return result
    }

    static func processApplePay(amountText: String, merchant: String, card: String, ctx: ModelContext) -> String {
        let result: String
        if let amount = SMSParser.parseNumber(amountText.filter { "0123456789., \u{00A0}\u{202F}".contains($0) }), amount > 0 {
            let up = amountText.uppercased()
            let currency = up.contains("$") || up.contains("USD") ? "USD"
                : up.contains("€") || up.contains("EUR") ? "EUR"
                : up.contains("₽") || up.contains("RUB") ? "RUB" : "UZS"
            let digits = card.filter(\.isNumber)
            let m = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            let e = BankEvent(text: "\(amountText) · \(m) · \(card)", tag: "Apple Pay", source: .applePay, hint: card,
                              amount: amount, currency: currency, kind: .expense,
                              last4: digits.count >= 4 ? String(digits.suffix(4)) : nil,
                              balance: nil, balanceCurrency: nil, merchant: m, merchantQuality: m.isEmpty ? 0 : 2,
                              cardName: card)
            result = ingest(e, ctx: ctx)
        } else {
            result = "Summa noto'g'ri: \(amountText)"
        }
        AutomationLog.add(source: TxSource.applePay.title, app: card, input: "\(amountText) · \(merchant)", result: result)
        return result
    }

    private static func ingest(text: String, tag: String, source: TxSource, hint: String, ctx: ModelContext) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = SMSParser.parse(trimmed) else { return "Matnda summa topilmadi, hech narsa yozilmadi." }
        let quoted = SMSParser.quoted(in: trimmed)
        var merchant = quoted ?? p.merchant
        if let phone = SMSParser.phoneCompact(in: trimmed) {
            let pretty = SMSParser.prettyPhone(phone)
            merchant = merchant.isEmpty ? pretty : "\(merchant) \(pretty)"
        }
        let e = BankEvent(text: trimmed, tag: tag, source: source, hint: hint, amount: p.amount, currency: p.currency,
                          kind: p.isIncome ? .income : .expense, last4: p.last4, balance: p.balance,
                          balanceCurrency: p.balanceCurrency, merchant: merchant,
                          merchantQuality: quoted != nil ? 2 : (merchant.isEmpty ? 0 : 1))
        return ingest(e, ctx: ctx)
    }

    // MARK: Pipeline

    private static func ingest(_ e: BankEvent, ctx: ModelContext) -> String {
        if isDuplicate(e.stored, ctx: ctx) { return "Bu xabar allaqachon yozilgan." }
        let all = accounts(ctx).filter { !$0.isArchived }
        let r = resolveAccount(e, all: all, ctx: ctx)
        guard let acc = r.account else { return "Hisob topilmadi. Avval MyFin'da karta qo'shing." }
        let confirmed = isConfirming(e, account: acc, byCard: r.byCard)
        var lines: [String] = []

        if let amount = e.amount, amount > 0 {
            if let t = findMatch(e, account: acc, byCard: r.byCard, confirmed: confirmed, ctx: ctx) {
                absorb(e, into: t, account: acc, byCard: r.byCard, confirmed: confirmed, ctx: ctx)
                lines.append("Bitta to'lov: xabar “\(t.title)” operatsiyasiga qo'shildi"
                             + (t.provisional ? " (bank tasdig'i kutilmoqda)." : " ✓ bank tasdiqladi."))
            } else {
                let tx = create(e, amount: amount, account: acc, confirmed: confirmed, ctx: ctx)
                let signed = e.kind == .income ? amount : -amount
                lines.append("\(tx.title): \(Money.format(signed, e.currency, signed: true))"
                             + (confirmed ? " ✓" : " · tasdiqlanmagan — bank xabari kelsa birlashadi"))
                if !tx.provisional, let note = detectTransfer(tx, ctx: ctx) { lines.append(note) }
            }
        }

        let sender = senderKey(e)
        let issuerCards = sender.map { s in all.filter { issuerKey(of: $0) == s }.count } ?? 0
        let balanceOwnerKnown = r.byCard || (sender != nil && !aggregatorKeys.contains(sender!) && issuerCards == 1)
        if e.balance != nil && !balanceOwnerKnown {
            lines.append("Xabarda karta raqami yo'q — qoldiq qaysi kartaga tegishli ekani aniq emas, balans o'zgartirilmadi.")
        }
        if let balance = e.balance, balanceOwnerKnown {
            lines.append(contentsOf: syncBalance(acc, bankValue: balance, currency: e.balanceCurrency ?? acc.currency,
                                                 created: r.created, ctx: ctx))
        } else {
            lines.append("\(acc.displayName): \(Money.format(acc.balance, acc.currency))")
        }
        if confirmed { SourceStatus.markConfirmed(acc.id, tag: e.tag) }
        if r.created { lines.append("Yangi karta qo'shildi (•\(acc.cardLast4)).") }
        try? ctx.save()
        WidgetSync.schedule(ctx)
        return lines.joined(separator: "\n")
    }

    private static func resolveAccount(_ e: BankEvent, all: [Account], ctx: ModelContext)
        -> (account: Account?, byCard: Bool, created: Bool) {
        let sender = senderKey(e).flatMap { aggregatorKeys.contains($0) ? nil : $0 }
        if let last4 = e.last4 {
            if let a = all.first(where: { $0.cardLast4 == last4 }) { return (a, true, false) }
            if let s = sender, let a = all.first(where: { issuerKey(of: $0) == s && $0.cardLast4.isEmpty }) {
                a.cardLast4 = last4
                return (a, true, false)
            }
            let name = sender.flatMap { s in knownBanks.first { $0.key == s }?.name }
            let a = Account(name: name ?? "Karta", kind: .card, bank: name ?? "", cardLast4: last4,
                            currency: e.balanceCurrency ?? e.currency, balance: 0,
                            colorHex: Palette.swatches.randomElement() ?? "#4F7CFF", sortOrder: all.count)
            ctx.insert(a)
            return (a, true, true)
        }
        if !e.cardName.isEmpty {
            let low = e.cardName.lowercased()
            if let a = all.first(where: { a in
                let n = a.name.lowercased(), b = a.bank.lowercased()
                return (n.count >= 3 && low.contains(n)) || (b.count >= 3 && low.contains(b))
            }) { return (a, false, false) }
            if let key = knownBank(in: e.cardName)?.key, let a = all.first(where: { issuerKey(of: $0) == key }) {
                return (a, false, false)
            }
        }
        if let s = sender, let a = all.first(where: { issuerKey(of: $0) == s }) { return (a, false, false) }
        return (defaultAutomationAccount(ctx), false, false)
    }

    /// A message confirms a payment when it names the card and comes from that card's own bank (app or SMS).
    private static func isConfirming(_ e: BankEvent, account: Account, byCard: Bool) -> Bool {
        guard byCard, e.source != .applePay else { return false }
        if e.source == .sms { return true }
        if let s = senderKey(e), aggregatorKeys.contains(s) { return false }
        guard let issuer = issuerKey(of: account) else { return true }
        return senderKey(e) == issuer
    }

    private static func recentAutomationTxs(_ ctx: ModelContext) -> [FinTransaction] {
        let since = Date().addingTimeInterval(-matchWindow)
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        return txs.prefix(40).filter { $0.date >= since && automationSources.contains($0.sourceRaw) && $0.kind != .transfer }
    }

    private static func findMatch(_ e: BankEvent, account acc: Account, byCard: Bool, confirmed: Bool,
                                  ctx: ModelContext) -> FinTransaction? {
        guard let amount = e.amount else { return nil }
        let myTag = e.tag.lowercased()
        let candidates = recentAutomationTxs(ctx).filter { t in
            guard t.kind == e.kind, t.currency == e.currency, !chunkTags(t.rawText).contains(myTag) else { return false }
            let tConfirmed = !t.provisional
            if confirmed && tConfirmed {
                // The same payment reported by the bank twice (SMS and app) — same card, exact amount.
                return t.accountID == acc.id
            }
            if byCard {
                if tConfirmed && t.accountID != acc.id { return false }
                if !tConfirmed, let tl = SMSParser.last4(in: t.rawText), tl != e.last4 { return false }
            }
            return true
        }
        func exact(_ t: FinTransaction) -> Bool { abs(t.amount - amount) < 0.01 }
        func withFee(_ t: FinTransaction) -> Bool {
            guard confirmed != !t.provisional else { return false }
            let bankAmount = confirmed ? amount : t.amount
            let otherAmount = confirmed ? t.amount : amount
            return bankAmount > otherAmount && bankAmount - otherAmount <= max(1, otherAmount * 0.015)
        }
        return candidates.first(where: exact) ?? candidates.first(where: withFee)
    }

    private static func absorb(_ e: BankEvent, into t: FinTransaction, account acc: Account, byCard: Bool,
                               confirmed: Bool, ctx: ModelContext) {
        let tHasCard = SMSParser.last4(in: t.rawText) != nil
        let moveTo: UUID? = byCard && (t.provisional || !tHasCard) && t.accountID != acc.id ? acc.id : nil
        var newAmount = t.amount
        if confirmed && t.provisional, let a = e.amount, abs(a - t.amount) >= 0.01 {
            let fee = a - t.amount
            newAmount = a
            if fee > 0 {
                let feeNote = "komissiya \(Money.format(fee, t.currency))"
                t.note = t.note.isEmpty ? feeNote : t.note + " · " + feeNote
            }
        }
        if moveTo != nil || newAmount != t.amount {
            if t.balanceApplied { applyEffect(of: t, sign: -1, ctx: ctx) }
            if let moveTo { t.accountID = moveTo }
            t.amount = newAmount
            if t.balanceApplied { applyEffect(of: t, sign: 1, ctx: ctx) }
        }
        let existingQuality = SMSParser.quoted(in: t.rawText) != nil || t.source == .applePay ? 2 : (t.merchant.isEmpty ? 0 : 1)
        if e.merchantQuality > existingQuality && !e.merchant.isEmpty {
            t.merchant = e.merchant
            if t.needsReview {
                t.categoryName = guessCategory(text: e.merchant + " " + e.text + " " + t.rawText, kind: t.kind, ctx: ctx)
            }
        }
        if confirmed { t.provisional = false }
        t.rawText += pairSeparator + e.stored
        try? ctx.save()
        if !t.provisional { _ = detectTransfer(t, ctx: ctx) }
    }

    private static func create(_ e: BankEvent, amount: Double, account acc: Account, confirmed: Bool,
                               ctx: ModelContext) -> FinTransaction {
        let category = guessCategory(text: e.merchant + " " + e.text, kind: e.kind, ctx: ctx)
        let tx = addTransaction(kind: e.kind, amount: amount, currency: e.currency, accountID: acc.id,
                                category: category, merchant: e.merchant,
                                note: e.source == .applePay ? "Apple Pay" : "", source: e.source,
                                rawText: e.stored, ctx: ctx)
        tx.provisional = !confirmed
        tx.needsReview = true
        try? ctx.save()
        Notifier.postReview(tx, account: acc)
        return tx
    }

    /// Expense on one own card + equal (or fee-smaller) income on another within the window → one transfer.
    @discardableResult
    private static func detectTransfer(_ tx: FinTransaction, ctx: ModelContext) -> String? {
        guard tx.kind != .transfer, let txAccount = tx.accountID else { return nil }
        let opposite: TxKind = tx.kind == .expense ? .income : .expense
        let other = recentAutomationTxs(ctx).first { o in
            guard o.id != tx.id, o.kind == opposite, let oa = o.accountID, oa != txAccount, !o.provisional else { return false }
            let out = tx.kind == .expense ? tx : o
            let inc = tx.kind == .expense ? o : tx
            let outV = out.amount
            let inV = RateStore.shared.convert(inc.amount, from: inc.currency, to: out.currency)
            return outV >= inV - 0.01 && outV - inV <= max(1, inV * 0.015)
        }
        guard let other else { return nil }
        let out = tx.kind == .expense ? tx : other
        let inc = tx.kind == .expense ? other : tx
        if out.balanceApplied { applyEffect(of: out, sign: -1, ctx: ctx) }
        if inc.balanceApplied { applyEffect(of: inc, sign: -1, ctx: ctx) }
        let toAccount = account(inc.accountID, in: ctx)
        out.kind = .transfer
        out.toAccountID = inc.accountID
        out.toAmount = RateStore.shared.convert(inc.amount, from: inc.currency, to: toAccount?.currency ?? inc.currency)
        out.categoryName = ""
        out.merchant = ""
        out.needsReview = false
        out.balanceApplied = true
        out.rawText += pairSeparator + inc.rawText
        applyEffect(of: out, sign: 1, ctx: ctx)
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["review-\(out.id.uuidString)", "review-\(inc.id.uuidString)"])
        ctx.delete(inc)
        try? ctx.save()
        let from = account(out.accountID, in: ctx)?.displayName ?? "—"
        return "O'z kartalaringiz orasidagi o'tkazma: \(from) → \(toAccount?.displayName ?? "—")."
    }

    // MARK: Balance check

    private static func syncBalance(_ acc: Account, bankValue: Double, currency: String, created: Bool,
                                    ctx: ModelContext) -> [String] {
        var lines: [String] = []
        let bankBalance = RateStore.shared.convert(bankValue, from: currency, to: acc.currency)
        let diff = bankBalance - acc.balance
        let tolerance = acc.currency == "UZS" ? 1.0 : 0.01
        let checkOn = UserDefaults.standard.object(forKey: "balanceCheck") as? Bool ?? true
        if checkOn && !created && currency == acc.currency && abs(diff) >= tolerance {
            let suspect = mismatchSuspect(acc, diff: diff, ctx: ctx)
            Notifier.postBalanceMismatch(account: acc, bank: bankBalance, local: acc.balance, diff: diff, suspect: suspect)
            var line = "⚠️ Balans mos emas — bankda \(Money.format(bankBalance, acc.currency)), MyFin'da \(Money.format(acc.balance, acc.currency)), farq \(Money.format(diff, acc.currency, signed: true))."
            if let s = suspect {
                line += s.action == "removeDup" ? " Ehtimol “\(s.tx.title)” ortiqcha yozilgan." : " Ehtimol “\(s.tx.title)” boshqa kartaga yozilgan."
            }
            lines.append(line)
        }
        acc.balance = bankBalance
        SourceStatus.markBalance(acc.id)
        lines.append("\(acc.displayName) balansi: \(Money.format(acc.balance, acc.currency))")
        return lines
    }

    /// diff > 0: MyFin took off more than the bank — a duplicate on this card. diff < 0: the bank took off more —
    /// an unconfirmed expense of that size may be sitting on another card.
    static func mismatchSuspect(_ acc: Account, diff: Double, ctx: ModelContext) -> (tx: FinTransaction, action: String)? {
        let since = Date().addingTimeInterval(-24 * 3600)
        let txs = ((try? ctx.fetch(FetchDescriptor<FinTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [])
            .prefix(200).filter { $0.date >= since && $0.kind == .expense }
        let target = abs(diff)
        func near(_ t: FinTransaction) -> Bool {
            abs(RateStore.shared.convert(t.amount, from: t.currency, to: acc.currency) - target) <= 1
        }
        if diff > 0 {
            let onCard = txs.filter { $0.accountID == acc.id && near($0) }
            if let t = onCard.first(where: \.provisional) ?? onCard.first(where: { automationSources.contains($0.sourceRaw) }) {
                return (t, "removeDup")
            }
        } else if let t = txs.first(where: { $0.accountID != acc.id && $0.provisional && near($0) }) {
            return (t, "moveHere")
        }
        return nil
    }

    /// The card's balance already equals the bank's, so the duplicate goes without touching it.
    static func removeDuplicate(txID: UUID, ctx: ModelContext) {
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>())) ?? []
        guard let t = txs.first(where: { $0.id == txID }) else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["review-\(t.id.uuidString)"])
        ctx.delete(t)
        try? ctx.save()
        WidgetSync.schedule(ctx)
    }

    /// Moves a misplaced expense to the card whose balance was just synced: the wrong card gets its money back,
    /// the synced card keeps the bank's figure.
    static func moveTransaction(txID: UUID, to accountID: UUID, ctx: ModelContext) {
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>())) ?? []
        guard let t = txs.first(where: { $0.id == txID }), let target = account(accountID, in: ctx) else { return }
        let keep = target.balance
        if t.balanceApplied { applyEffect(of: t, sign: -1, ctx: ctx) }
        t.accountID = accountID
        t.provisional = false
        if t.balanceApplied { applyEffect(of: t, sign: 1, ctx: ctx) }
        target.balance = keep
        try? ctx.save()
        WidgetSync.schedule(ctx)
    }
}

/// Per-card record of the last confirming bank message and balance sync, for the status list in settings.
enum SourceStatus {
    static func markConfirmed(_ id: UUID, tag: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "srcAt-\(id.uuidString)")
        UserDefaults.standard.set(tag, forKey: "srcTag-\(id.uuidString)")
    }

    static func markBalance(_ id: UUID) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "balAt-\(id.uuidString)")
    }

    static func lastConfirmed(_ id: UUID) -> (date: Date, tag: String)? {
        let t = UserDefaults.standard.double(forKey: "srcAt-\(id.uuidString)")
        guard t > 0 else { return nil }
        return (Date(timeIntervalSince1970: t), UserDefaults.standard.string(forKey: "srcTag-\(id.uuidString)") ?? "")
    }

    static func lastBalance(_ id: UUID) -> Date? {
        let t = UserDefaults.standard.double(forKey: "balAt-\(id.uuidString)")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
}
