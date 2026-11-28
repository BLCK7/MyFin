import Foundation
import SwiftData
import UserNotifications
import LocalAuthentication

enum Notifier {
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func cancel(_ ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func scheduleDebt(id: UUID, person: String, amountText: String, direction: DebtDirection, due: Date?, enabled: Bool) {
        let ids = ["debt-\(id.uuidString)-before", "debt-\(id.uuidString)-day"]
        cancel(ids)
        guard enabled, let due else { return }
        let cal = Calendar.current
        let title = direction == .iOwe ? "Qarz to'lash muddati" : "Qarz qaytarish muddati"
        let bodyDay = direction == .iOwe
            ? "Bugun \(person)ga \(amountText) qaytarishingiz kerak."
            : "Bugun \(person) sizga \(amountText) qaytarishi kerak."
        let bodyBefore = direction == .iOwe
            ? "Ertaga \(person)ga \(amountText) qaytarish muddati."
            : "Ertaga \(person) sizga \(amountText) qaytarishi kerak."
        var dayComps = cal.dateComponents([.year, .month, .day], from: due)
        dayComps.hour = 10
        add(id: ids[1], title: title, body: bodyDay, comps: dayComps, repeats: false)
        if let before = cal.date(byAdding: .day, value: -1, to: due) {
            var bc = cal.dateComponents([.year, .month, .day], from: before)
            bc.hour = 19
            add(id: ids[0], title: title, body: bodyBefore, comps: bc, repeats: false)
        }
    }

    static func scheduleRecurring(id: UUID, name: String, amountText: String, day: Int, enabled: Bool) {
        let rid = "recurring-\(id.uuidString)"
        cancel([rid])
        guard enabled else { return }
        var comps = DateComponents()
        comps.day = max(1, min(28, day))
        comps.hour = 10
        add(id: rid, title: "Doimiy to'lov: \(name)", body: "Bugun \(amountText) to'lash kuni.", comps: comps, repeats: true)
    }

    static func notifyNow(title: String, body: String, id: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private static func add(id: String, title: String, body: String, comps: DateComponents, repeats: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

enum Biometrics {
    static var available: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static var icon: String {
        let ctx = LAContext()
        var error: NSError?
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return ctx.biometryType == .touchID ? "touchid" : "faceid"
    }

    static func authenticateBiometric(reason: String) async -> Bool {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "PIN-kod"
        ctx.localizedCancelTitle = "Bekor"
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return false }
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            return false
        }
    }

    static var name: String {
        let ctx = LAContext()
        var error: NSError?
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Parol"
        }
    }

    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

extension Notifier {
    static let reviewExpenseCategory = "TX_REVIEW_EXP"
    static let reviewIncomeCategory = "TX_REVIEW_INC"
    static let balanceMismatchCategory = "BAL_MISMATCH"
    static let balanceDuplicateCategory = "BAL_MISMATCH_DUP"
    static let balanceMoveCategory = "BAL_MISMATCH_MOVE"

    @MainActor
    static func registerReviewCategories(_ context: ModelContext? = nil) {
        let ctx = context ?? DataStore.context
        let comment = UNTextInputNotificationAction(identifier: "comment", title: "Izoh / kategoriya yozish",
                                                    options: [], textInputButtonTitle: "Saqlash",
                                                    textInputPlaceholder: "masalan: ovqat — tushlik")
        let open = UNNotificationAction(identifier: "open", title: "Ochish", options: [.foreground])
        func actions(_ kind: TxKind) -> [UNNotificationAction] {
            let top = FinanceEngine.topCategories(kind: kind, limit: 4, ctx: ctx)
            var list: [UNNotificationAction] = [comment]
            for name in top {
                list.append(UNNotificationAction(identifier: "cat:\(name)", title: name, options: []))
            }
            list.append(open)
            return list
        }
        let exp = UNNotificationCategory(identifier: reviewExpenseCategory, actions: actions(.expense),
                                         intentIdentifiers: [], options: [.customDismissAction])
        let inc = UNNotificationCategory(identifier: reviewIncomeCategory, actions: actions(.income),
                                         intentIdentifiers: [], options: [.customDismissAction])
        let recordDiff = UNNotificationAction(identifier: "recordDiff", title: "Farqni operatsiya sifatida yozish", options: [])
        let openApp = UNNotificationAction(identifier: "open", title: "Ochish", options: [.foreground])
        let bal = UNNotificationCategory(identifier: balanceMismatchCategory, actions: [recordDiff, openApp],
                                         intentIdentifiers: [], options: [])
        let dup = UNNotificationCategory(
            identifier: balanceDuplicateCategory,
            actions: [UNNotificationAction(identifier: "removeDup", title: "Ortiqchasini o'chirish", options: [.destructive]),
                      recordDiff, openApp],
            intentIdentifiers: [], options: [])
        let move = UNNotificationCategory(
            identifier: balanceMoveCategory,
            actions: [UNNotificationAction(identifier: "moveHere", title: "Shu kartaga ko'chirish", options: []),
                      recordDiff, openApp],
            intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([exp, inc, bal, dup, move])
    }

    @MainActor
    static func postBalanceMismatch(account: Account, bank: Double, local: Double, diff: Double,
                                    suspect: (tx: FinTransaction, action: String)? = nil) {
        guard !Sandbox.active else { return }
        let content = UNMutableNotificationContent()
        content.title = "Balans mos emas · \(account.displayName)"
        var hint = diff < 0 ? "Yozilmagan operatsiya bo'lishi mumkin." : "Biror operatsiya ortiqcha yozilgan bo'lishi mumkin."
        if let s = suspect {
            let what = "“\(s.tx.title)” (\(Money.format(s.tx.amount, s.tx.currency)), \(s.tx.date.formatted(date: .omitted, time: .shortened)))"
            hint = s.action == "removeDup" ? "Ehtimol \(what) ikki marta yozilgan." : "Ehtimol \(what) boshqa kartaga yozilgan."
        }
        content.body = "Bankda: \(Money.format(bank, account.currency)) · MyFin'da: \(Money.format(local, account.currency)) · Farq: \(Money.format(diff, account.currency, signed: true)). \(hint) Balans bank bo'yicha yangilandi."
        content.sound = .default
        content.threadIdentifier = "balance-check"
        var info: [String: Any] = ["balanceAccountID": account.id.uuidString, "diff": diff]
        if let s = suspect {
            info["suspectTxID"] = s.tx.id.uuidString
            content.categoryIdentifier = s.action == "removeDup" ? balanceDuplicateCategory : balanceMoveCategory
        } else {
            content.categoryIdentifier = balanceMismatchCategory
        }
        content.userInfo = info
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "balance-\(account.id.uuidString)", content: content, trigger: nil))
    }

    @MainActor
    static func postReview(_ tx: FinTransaction, account: Account?) {
        guard !Sandbox.active else { return }
        guard UserDefaults.standard.object(forKey: "reviewNotifications") as? Bool ?? true else { return }
        let content = UNMutableNotificationContent()
        let signed = tx.kind == .income ? tx.amount : -tx.amount
        content.title = "\(Money.format(signed, tx.currency, signed: true)) · \(tx.title)"
        let acc = account?.displayName ?? ""
        content.body = "\(acc.isEmpty ? "" : acc + " · ")\(tx.categoryName). Izoh va kategoriya qo'shish uchun bosib turing."
        content.sound = .default
        content.categoryIdentifier = tx.kind == .income ? reviewIncomeCategory : reviewExpenseCategory
        content.threadIdentifier = "tx-review"
        content.userInfo = ["txID": tx.id.uuidString]
        let req = UNNotificationRequest(identifier: "review-\(tx.id.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    static func scheduleExpiry(id: UUID, title: String, date: Date?) {
        let ids = ["vault-\(id.uuidString)-30", "vault-\(id.uuidString)-7"]
        cancel(ids)
        guard let date, date > Date() else { return }
        let cal = Calendar.current
        for (offset, rid) in [(-30, ids[0]), (-7, ids[1])] {
            guard let d = cal.date(byAdding: .day, value: offset, to: date), d > Date() else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: d)
            comps.hour = 10
            let content = UNMutableNotificationContent()
            content.title = "Hujjat muddati tugayapti"
            content.body = "\(title): \(-offset) kundan keyin amal qilish muddati tugaydi."
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: rid, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}
