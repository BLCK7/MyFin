import AppIntents
import UniformTypeIdentifiers
import SwiftData

// MARK: Entities

struct AccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Hisob"
    static let defaultQuery = AccountQuery()

    let id: UUID
    let name: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }
}

struct AccountQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        await MainActor.run { Self.all().filter { identifiers.contains($0.id) } }
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        await MainActor.run { Self.all() }
    }

    @MainActor
    static func all() -> [AccountEntity] {
        FinanceEngine.accounts(DataStore.context).filter { !$0.isArchived }.map {
            AccountEntity(id: $0.id, name: $0.displayName, subtitle: $0.kind.title)
        }
    }
}

struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kategoriya"
    static let defaultQuery = CategoryQuery()

    let id: UUID
    let name: String
    let isIncome: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(isIncome ? "Kirim" : "Chiqim")")
    }
}

struct CategoryQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        await MainActor.run { Self.all().filter { identifiers.contains($0.id) } }
    }

    func suggestedEntities() async throws -> [CategoryEntity] {
        await MainActor.run { Self.all() }
    }

    @MainActor
    static func all() -> [CategoryEntity] {
        FinanceEngine.categories(DataStore.context).map {
            CategoryEntity(id: $0.id, name: $0.name, isIncome: $0.kind == .income)
        }
    }
}

// MARK: Shared logic

@MainActor
enum IntentLogic {
    static func base() -> String { UserDefaults.standard.string(forKey: "baseCurrency") ?? "UZS" }

    static func resolveAccount(_ entity: AccountEntity?, ctx: ModelContext) -> Account? {
        if let entity, let a = FinanceEngine.account(entity.id, in: ctx) { return a }
        return FinanceEngine.defaultAutomationAccount(ctx)
    }

    static func add(kind: TxKind, amount: Double, category: CategoryEntity?, note: String?,
                    account: AccountEntity?) -> String {
        let ctx = DataStore.context
        guard amount > 0, let acc = resolveAccount(account, ctx: ctx) else {
            return "Hisob topilmadi yoki summa noto'g'ri."
        }
        let text = note ?? ""
        var cat = category?.name ?? ""
        var review = false
        if cat.isEmpty {
            cat = FinanceEngine.guessCategory(text: text, kind: kind, ctx: ctx)
            review = cat == "Boshqa xarajat" || cat == "Boshqa kirim"
        }
        let tx = FinanceEngine.addTransaction(kind: kind, amount: amount, currency: acc.currency, accountID: acc.id,
                                              category: cat, merchant: "", note: text, source: .siri, ctx: ctx)
        if review {
            tx.needsReview = true
            try? ctx.save()
            Notifier.postReview(tx, account: acc)
        }
        let signed = kind == .income ? amount : -amount
        return "\(Money.format(signed, acc.currency, signed: true)) · \(cat). \(acc.displayName): \(Money.format(acc.balance, acc.currency))"
    }
}

// MARK: Intents

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Chiqim qo'shish"
    static let description = IntentDescription("Xarajat yozadi. Kategoriya berilmasa, izohdan aniqlanadi yoki keyin so'raladi.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Summa", requestValueDialog: "Qancha?")
    var amount: Double

    @Parameter(title: "Kategoriya")
    var category: CategoryEntity?

    @Parameter(title: "Izoh")
    var note: String?

    @Parameter(title: "Hisob")
    var account: AccountEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = IntentLogic.add(kind: .expense, amount: amount, category: category, note: note, account: account)
        return .result(dialog: "\(text)")
    }
}

struct AddIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Kirim qo'shish"
    static let description = IntentDescription("Daromad yozadi.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Summa", requestValueDialog: "Qancha?")
    var amount: Double

    @Parameter(title: "Kategoriya")
    var category: CategoryEntity?

    @Parameter(title: "Izoh")
    var note: String?

    @Parameter(title: "Hisob")
    var account: AccountEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = IntentLogic.add(kind: .income, amount: amount, category: category, note: note, account: account)
        return .result(dialog: "\(text)")
    }
}

struct TotalBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Umumiy balans"
    static let description = IntentDescription("Barcha hisoblardagi pul va sof boylikni aytadi.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let ctx = DataStore.context
        let debts = (try? ctx.fetch(FetchDescriptor<Debt>())) ?? []
        let base = IntentLogic.base()
        let s = FinanceEngine.summary(accounts: FinanceEngine.accounts(ctx), transactions: [], debts: debts,
                                      rates: RateStore.shared, base: base)
        let text = "Hisoblarda: \(Money.format(s.totalAssets, base)). Sof boylik: \(Money.format(s.netWorth, base))."
        return .result(value: s.totalAssets, dialog: "\(text)")
    }
}

struct AccountBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Hisob balansi"
    static let description = IntentDescription("Tanlangan karta yoki hisobdagi qoldiqni aytadi.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Hisob", requestValueDialog: "Qaysi hisob?")
    var account: AccountEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        guard let a = FinanceEngine.account(account.id, in: DataStore.context) else {
            return .result(value: 0, dialog: "Hisob topilmadi.")
        }
        return .result(value: a.balance, dialog: "\(a.displayName): \(Money.format(a.balance, a.currency))")
    }
}

struct TodaySpendingIntent: AppIntent {
    static let title: LocalizedStringResource = "Bugungi xarajat"
    static let description = IntentDescription("Bugun va shu oy qancha sarflanganini aytadi.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let ctx = DataStore.context
        let base = IntentLogic.base()
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>())) ?? []
        let cal = Calendar.current
        var today = 0.0
        for t in txs where t.kind == .expense && cal.isDateInToday(t.date) {
            today += RateStore.shared.convert(t.amount, from: t.currency, to: base)
        }
        let s = FinanceEngine.summary(accounts: [], transactions: txs, debts: [], rates: RateStore.shared, base: base)
        let text = "Bugun: \(Money.format(today, base)). Shu oy: \(Money.format(s.monthExpense, base))."
        return .result(value: today, dialog: "\(text)")
    }
}

struct OpenNewTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Yangi operatsiya oynasi"
    static let description = IntentDescription("MyFin'ni yangi chiqim oynasi bilan ochadi.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.addKind = .expense
        return .result()
    }
}

struct ScanReceiptIntent: AppIntent {
    static let title: LocalizedStringResource = "Soliq chekini skanerlash"
    static let description = IntentDescription("MyFin'ni chek QR kodini skanerlash oynasi bilan ochadi.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.capture = .scan
        return .result()
    }
}

struct LogScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Skrinshotdan yozish"
    static let description = IntentDescription("Bank ilovasi yoki Wallet bildirishnomasi skrinshotidan summa, karta va do'konni o'qib, operatsiyani yozadi.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Rasm", supportedContentTypes: [.image])
    var image: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let read = await ImageReader.read(image.data)
        guard !read.text.isEmpty else {
            return .result(dialog: "Rasmda matn topilmadi.")
        }
        let summary = FinanceEngine.processScreenshotText(read.text, ctx: DataStore.context)
        return .result(dialog: "\(summary)")
    }
}

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
    static let description = IntentDescription("Bank ilovasi yoki Telegram bot (CardXabar, HUMO) bildirishnomasidan operatsiya va balansni yozadi.")
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

struct MyFinShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TotalBalanceIntent(),
                    phrases: ["\(.applicationName) balance",
                              "Show my balance in \(.applicationName)",
                              "How much money do I have in \(.applicationName)"],
                    shortTitle: "Balans", systemImageName: "banknote.fill")
        AppShortcut(intent: AddExpenseIntent(),
                    phrases: ["Add expense in \(.applicationName)",
                              "Log expense in \(.applicationName)",
                              "\(.applicationName) expense"],
                    shortTitle: "Chiqim qo'shish", systemImageName: "minus.circle.fill")
        AppShortcut(intent: AddIncomeIntent(),
                    phrases: ["Add income in \(.applicationName)",
                              "\(.applicationName) income"],
                    shortTitle: "Kirim qo'shish", systemImageName: "plus.circle.fill")
        AppShortcut(intent: TodaySpendingIntent(),
                    phrases: ["How much did I spend today in \(.applicationName)",
                              "\(.applicationName) today"],
                    shortTitle: "Bugungi xarajat", systemImageName: "calendar")
        AppShortcut(intent: AccountBalanceIntent(),
                    phrases: ["Card balance in \(.applicationName)",
                              "Account balance in \(.applicationName)"],
                    shortTitle: "Karta balansi", systemImageName: "creditcard.fill")
        AppShortcut(intent: OpenNewTransactionIntent(),
                    phrases: ["New transaction in \(.applicationName)",
                              "Open \(.applicationName) new transaction"],
                    shortTitle: "Yangi operatsiya", systemImageName: "square.and.pencil")
        AppShortcut(intent: ScanReceiptIntent(),
                    phrases: ["Scan receipt in \(.applicationName)",
                              "\(.applicationName) receipt"],
                    shortTitle: "Chek skanerlash", systemImageName: "qrcode.viewfinder")
        AppShortcut(intent: LogBankSMSIntent(),
                    phrases: ["\(.applicationName) bank SMS"],
                    shortTitle: "Bank SMS", systemImageName: "message.fill")
        AppShortcut(intent: LogBankNotificationIntent(),
                    phrases: ["\(.applicationName) bank notification"],
                    shortTitle: "Bank bildirishnomasi", systemImageName: "bell.badge.fill")
        AppShortcut(intent: LogApplePayIntent(),
                    phrases: ["\(.applicationName) Apple Pay"],
                    shortTitle: "Apple Pay", systemImageName: "apple.logo")
    }
}
