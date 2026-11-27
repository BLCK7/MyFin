import AppIntents
import SwiftData

struct LogBankSMSIntent: AppIntent {
    static let title: LocalizedStringResource = "Bank SMS'ini yozish"
    static let description = IntentDescription("Uzcard yoki HUMO SMS matnidan operatsiyani va karta balansini MyFin'ga yozadi.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "SMS matni")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = FinanceEngine.processSMS(text, ctx: DataStore.context)
        return .result(dialog: "\(summary)")
    }
}

struct LogBankNotificationIntent: AppIntent {
    static let title: LocalizedStringResource = "Bank bildirishnomasini yozish"
    static let description = IntentDescription("Bank ilovasi bildirishnomasidan (Uzum, TBC, Kapitalbank, Click, Payme…) operatsiya va balansni MyFin'ga yozadi.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Matn")
    var body: String

    @Parameter(title: "Sarlavha", default: "")
    var heading: String

    @Parameter(title: "Ilova", default: "")
    var app: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = FinanceEngine.processNotification(title: heading, body: body, app: app, ctx: DataStore.context)
        return .result(dialog: "\(summary)")
    }
}

struct LogApplePayIntent: AppIntent {
    static let title: LocalizedStringResource = "Apple Pay xaridini yozish"
    static let description = IntentDescription("Wallet tranzaksiyasini (summa, do'kon, karta) MyFin'ga chiqim sifatida yozadi.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Summa")
    var amount: String

    @Parameter(title: "Do'kon", default: "")
    var merchant: String

    @Parameter(title: "Karta", default: "")
    var card: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = FinanceEngine.processApplePay(amountText: amount, merchant: merchant, card: card, ctx: DataStore.context)
        return .result(dialog: "\(summary)")
    }
}

struct QuickExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Tezkor xarajat qo'shish"
    static let description = IntentDescription("Asosiy hisobdan tezkor chiqim yozadi.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Summa")
    var amount: Double

    @Parameter(title: "Izoh", default: "")
    var note: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = DataStore.context
        guard amount > 0, let acc = FinanceEngine.defaultAutomationAccount(ctx) else {
            return .result(dialog: "Hisob topilmadi yoki summa noto'g'ri.")
        }
        let category = FinanceEngine.guessCategory(text: note, kind: .expense, ctx: ctx)
        FinanceEngine.addTransaction(kind: .expense, amount: amount, currency: acc.currency, accountID: acc.id,
                                     category: category, merchant: note, source: .siri, ctx: ctx)
        let text = "\(Money.format(-amount, acc.currency, signed: true)) yozildi. \(acc.displayName): \(Money.format(acc.balance, acc.currency))"
        return .result(dialog: "\(text)")
    }
}

struct TotalBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Umumiy balans"
    static let description = IntentDescription("Barcha hisoblardagi pul va sof boylikni aytadi.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = DataStore.context
        let accounts = FinanceEngine.accounts(ctx)
        let debts = (try? ctx.fetch(FetchDescriptor<Debt>())) ?? []
        let base = UserDefaults.standard.string(forKey: "baseCurrency") ?? "UZS"
        let s = FinanceEngine.summary(accounts: accounts, transactions: [], debts: debts, rates: RateStore.shared, base: base)
        let text = "Hisoblarda: \(Money.format(s.totalAssets, base)). Sof boylik: \(Money.format(s.netWorth, base))."
        return .result(dialog: "\(text)")
    }
}

struct MyFinShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TotalBalanceIntent(),
                    phrases: ["\(.applicationName) balans", "\(.applicationName)da qancha pulim bor"],
                    shortTitle: "Balans", systemImageName: "banknote.fill")
        AppShortcut(intent: QuickExpenseIntent(),
                    phrases: ["\(.applicationName) xarajat", "\(.applicationName)ga xarajat qo'sh"],
                    shortTitle: "Tezkor xarajat", systemImageName: "minus.circle.fill")
        AppShortcut(intent: LogBankSMSIntent(),
                    phrases: ["\(.applicationName) bank SMS"],
                    shortTitle: "Bank SMS", systemImageName: "message.fill")
        AppShortcut(intent: LogBankNotificationIntent(),
                    phrases: ["\(.applicationName) bildirishnoma"],
                    shortTitle: "Bank bildirishnomasi", systemImageName: "bell.badge.fill")
        AppShortcut(intent: LogApplePayIntent(),
                    phrases: ["\(.applicationName) Apple Pay"],
                    shortTitle: "Apple Pay", systemImageName: "creditcard.fill")
    }
}
