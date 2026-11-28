import Foundation
import SwiftData

/// Launch arguments used by the UI tests in CI:
/// `-uitest` runs on an in-memory store with clean settings and no splash;
/// `-uitest-demo` additionally skips onboarding, sets PIN 135790 and fills demo cards and operations.
enum UITestSupport {
    static let isActive = ProcessInfo.processInfo.arguments.contains("-uitest")
    static let demo = ProcessInfo.processInfo.arguments.contains("-uitest-demo")
    static let demoPIN = "135790"

    @MainActor
    static func prepareDefaults() {
        guard isActive else { return }
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        PasscodeStore.clear()
        UserDefaults.standard.set(false, forKey: "reviewNotifications")
        if demo {
            PasscodeStore.set(demoPIN)
            UserDefaults.standard.set(true, forKey: "onboarded")
            UserDefaults.standard.set("Test", forKey: "userName")
        }
    }

    @MainActor
    static func seedDemo(_ ctx: ModelContext) {
        guard demo, FinanceEngine.accounts(ctx).isEmpty else { return }
        let cash = Account(name: "Naqd pul", kind: .cash, balance: 150_000, colorHex: "#10B981", sortOrder: 0)
        let humo = Account(name: "Humo", kind: .card, bank: "TBC", cardLast4: "9300", balance: 50_000,
                           colorHex: "#4F7CFF", sortOrder: 1)
        let visa = Account(name: "Visa", kind: .card, bank: "TBC", cardLast4: "7758", balance: 2_530.34,
                           colorHex: "#7C3AED", sortOrder: 2)
        let uzum = Account(name: "Uzum Visa", kind: .card, bank: "Uzum", cardLast4: "7675", balance: 80_000,
                           colorHex: "#9333EA", sortOrder: 3)
        let usd = Account(name: "Naqd dollar", kind: .cash, currency: "USD", balance: 100, colorHex: "#0EA5E9", sortOrder: 4)
        [cash, humo, visa, uzum, usd].forEach { ctx.insert($0) }
        try? ctx.save()

        FinanceEngine.addTransaction(kind: .income, amount: 5_000_000, currency: "UZS", accountID: humo.id,
                                     category: "Maosh", merchant: "Ish haqi", ctx: ctx)
        FinanceEngine.addTransaction(kind: .expense, amount: 45_000, currency: "UZS", accountID: visa.id,
                                     category: "Oziq-ovqat", merchant: "Korzinka", source: .applePay, ctx: ctx)
        FinanceEngine.addTransaction(kind: .expense, amount: 10, currency: "USD", accountID: visa.id,
                                     category: "Obunalar", merchant: "Claude.ai", ctx: ctx)
        FinanceEngine.addTransaction(kind: .transfer, amount: 30_000, currency: "UZS", accountID: humo.id,
                                     toAccountID: uzum.id, toAmount: 30_000, ctx: ctx)
        let pending = FinanceEngine.addTransaction(kind: .expense, amount: 20_000, currency: "UZS", accountID: humo.id,
                                                   category: "Aloqa va internet", merchant: "Beeline",
                                                   source: .notification, rawText: "[Payme] Payme: Beeline uchun 20 000 so'm to'landi",
                                                   ctx: ctx)
        pending.needsReview = true
        pending.provisional = true
        _ = FinanceEngine.addDebt(person: "Ali", direction: .owedToMe, amount: 100_000, currency: "UZS",
                                  dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()), note: "",
                                  reminder: false, moveMoney: true, accountID: cash.id, ctx: ctx)
        _ = FinanceEngine.addDebt(person: "Vali", direction: .iOwe, amount: 200_000, currency: "UZS",
                                  dueDate: nil, note: "", reminder: false, moveMoney: false, accountID: nil, ctx: ctx)
        ctx.insert(Budget(categoryName: "", limit: 3_000_000, period: .month))
        ctx.insert(Budget(categoryName: "Oziq-ovqat", limit: 300_000, period: .week))
        let goal = Goal(name: "Yangi telefon", icon: "iphone", colorHex: "#8B5CF6", target: 5_000_000)
        ctx.insert(goal)
        FinanceEngine.contribute(to: goal, amount: 50_000, accountID: cash.id, ctx: ctx)
        let internet = RecurringPayment(name: "Internet", amount: 100_000, accountID: humo.id,
                                        categoryName: "Aloqa va internet", dayOfMonth: 5)
        internet.reminder = false
        ctx.insert(internet)
        if let sealed = try? VaultCrypto.seal(VaultPayload(title: "Pasport (demo)", fields: [
            VaultField(label: "Seriya va raqam", value: "AA1234567"),
            VaultField(label: "JSHSHIR", value: "31234567890123")
        ])) {
            ctx.insert(VaultItem(kind: VaultKind.passport.rawValue, payload: sealed))
        }
        try? ctx.save()
    }
}
