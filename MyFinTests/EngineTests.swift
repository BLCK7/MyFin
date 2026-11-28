import XCTest
import SwiftData
@testable import MyFin

@MainActor
final class EngineTests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext!
    private var card: Account!
    private var cash: Account!

    override func setUp() async throws {
        Sandbox.active = true
        container = try ModelContainer(for: DataStore.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        ctx = container.mainContext
        SeedData.seedIfNeeded(ctx)
        card = Account(name: "Visa", kind: .card, bank: "TBC", cardLast4: "7758", balance: 1_000_000, sortOrder: 0)
        cash = Account(name: "Naqd", kind: .cash, balance: 500_000, sortOrder: 1)
        ctx.insert(card)
        ctx.insert(cash)
        try ctx.save()
    }

    override func tearDown() async throws {
        Sandbox.active = false
        container = nil
        ctx = nil
    }

    private var txs: [FinTransaction] { (try? ctx.fetch(FetchDescriptor<FinTransaction>())) ?? [] }
    private var debts: [Debt] { (try? ctx.fetch(FetchDescriptor<Debt>())) ?? [] }

    private func summary() -> FinanceSummary {
        FinanceEngine.summary(accounts: FinanceEngine.accounts(ctx), transactions: txs, debts: debts,
                              rates: RateStore.shared, base: "UZS")
    }

    // MARK: Statistics

    func testDebtAndGoalMovesAreNotIncomeOrExpense() {
        FinanceEngine.addTransaction(kind: .expense, amount: 40_000, currency: "UZS", accountID: card.id,
                                     category: "Oziq-ovqat", merchant: "Korzinka", ctx: ctx)
        FinanceEngine.addTransaction(kind: .income, amount: 3_000_000, currency: "UZS", accountID: card.id,
                                     category: "Maosh", ctx: ctx)
        _ = FinanceEngine.addDebt(person: "Ali", direction: .owedToMe, amount: 200_000, currency: "UZS", dueDate: nil,
                                  note: "", reminder: false, moveMoney: true, accountID: cash.id, ctx: ctx)
        _ = FinanceEngine.addDebt(person: "Vali", direction: .iOwe, amount: 300_000, currency: "UZS", dueDate: nil,
                                  note: "", reminder: false, moveMoney: true, accountID: card.id, ctx: ctx)
        let goal = Goal(name: "Telefon", icon: "iphone", colorHex: "#8B5CF6", target: 1_000_000)
        ctx.insert(goal)
        FinanceEngine.contribute(to: goal, amount: 100_000, accountID: cash.id, ctx: ctx)

        let s = summary()
        XCTAssertEqual(s.monthExpense, 40_000, accuracy: 0.01)
        XCTAssertEqual(s.monthIncome, 3_000_000, accuracy: 0.01)
        XCTAssertEqual(s.goalReserve, 100_000, accuracy: 0.01)
        // Assets: card 1 000 000 − 40 000 + 3 000 000 + 300 000; cash 500 000 − 200 000 − 100 000.
        XCTAssertEqual(s.totalAssets, 4_260_000 + 200_000, accuracy: 0.01)
        // Lending, borrowing and saving for a goal do not change net worth.
        XCTAssertEqual(s.netWorth, 1_500_000 + 3_000_000 - 40_000, accuracy: 0.01)

        let slices = FinanceEngine.spendingByCategory(transactions: txs, categories: FinanceEngine.categories(ctx),
                                                      rates: RateStore.shared, base: "UZS", month: Date())
        XCTAssertEqual(slices.map(\.name), ["Oziq-ovqat"])
    }

    func testBudgetsCountOnlyRealSpending() {
        let weekly = Budget(categoryName: "Oziq-ovqat", limit: 100_000, period: .week)
        let monthly = Budget(categoryName: "", limit: 1_000_000, period: .month)
        ctx.insert(weekly)
        ctx.insert(monthly)
        FinanceEngine.addTransaction(kind: .expense, amount: 30_000, currency: "UZS", accountID: card.id,
                                     category: "Oziq-ovqat", ctx: ctx)
        FinanceEngine.addTransaction(kind: .expense, amount: 50_000, currency: "UZS", accountID: card.id,
                                     category: "Transport", ctx: ctx)
        let old = FinanceEngine.addTransaction(kind: .expense, amount: 70_000, currency: "UZS", accountID: card.id,
                                               category: "Oziq-ovqat", ctx: ctx)
        old.date = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        _ = FinanceEngine.addDebt(person: "Ali", direction: .owedToMe, amount: 500_000, currency: "UZS", dueDate: nil,
                                  note: "", reminder: false, moveMoney: true, accountID: card.id, ctx: ctx)
        XCTAssertEqual(FinanceEngine.spent(budget: weekly, transactions: txs, rates: RateStore.shared, base: "UZS"), 30_000, accuracy: 0.01)
        XCTAssertEqual(FinanceEngine.spent(budget: monthly, transactions: txs, rates: RateStore.shared, base: "UZS"), 80_000, accuracy: 0.01)
        let daily = FinanceEngine.safeDaily(budget: monthly, spent: 80_000)
        XCTAssertGreaterThan(daily, 0)
        XCTAssertLessThanOrEqual(daily, 920_000)
    }

    func testWeekStartsOnMonday() {
        let interval = BudgetPeriod.week.interval()
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.weekday, from: interval.start), 2)
        XCTAssertEqual(interval.duration, 7 * 86_400, accuracy: 3_700)
    }

    // MARK: Balances

    func testDeleteRestoresBalanceAndTransferMovesBoth() {
        let t = FinanceEngine.addTransaction(kind: .expense, amount: 12_345.67, currency: "UZS", accountID: card.id, ctx: ctx)
        XCTAssertEqual(card.balance, 987_654.33, accuracy: 0.001)
        FinanceEngine.delete(t, ctx: ctx)
        XCTAssertEqual(card.balance, 1_000_000, accuracy: 0.001)

        FinanceEngine.addTransaction(kind: .transfer, amount: 100_000, currency: "UZS", accountID: card.id,
                                     toAccountID: cash.id, toAmount: 100_000, ctx: ctx)
        XCTAssertEqual(card.balance, 900_000, accuracy: 0.001)
        XCTAssertEqual(cash.balance, 600_000, accuracy: 0.001)
    }

    func testForeignCurrencyPurchaseConvertsForBalance() {
        RateStore.shared.rates["USD"] = 12_000
        FinanceEngine.addTransaction(kind: .expense, amount: 10, currency: "USD", accountID: card.id, ctx: ctx)
        XCTAssertEqual(card.balance, 1_000_000 - 120_000, accuracy: 0.001)
    }

    func testDebtPaymentClosesDebt() {
        let d = FinanceEngine.addDebt(person: "Vali", direction: .iOwe, amount: 300_000, currency: "UZS", dueDate: nil,
                                      note: "", reminder: false, moveMoney: false, accountID: nil, ctx: ctx)
        FinanceEngine.addDebtPayment(d, amount: 100_000, accountID: card.id, note: "", ctx: ctx)
        XCTAssertEqual(d.remaining, 200_000, accuracy: 0.01)
        XCTAssertFalse(d.isClosed)
        FinanceEngine.addDebtPayment(d, amount: 250_000, accountID: card.id, note: "", ctx: ctx)
        XCTAssertEqual(d.remaining, 0, accuracy: 0.01)
        XCTAssertTrue(d.isClosed)
        XCTAssertEqual(card.balance, 1_000_000 - 350_000, accuracy: 0.01)
        XCTAssertEqual(summary().monthExpense, 0, accuracy: 0.01)
    }

    // MARK: Money text

    func testEditStringKeepsTiyin() {
        XCTAssertEqual(Money.editString(1530.34, "UZS"), "1530,34")
        XCTAssertEqual(SMSParser.parseNumber(Money.editString(1530.34, "UZS")) ?? 0, 1530.34, accuracy: 0.001)
        XCTAssertEqual(Money.editString(2_000_000, "UZS"), "2000000")
        XCTAssertEqual(Money.editString(-469.66, "UZS").replacingOccurrences(of: "−", with: "-"), "-469,66")
        XCTAssertEqual(SMSParser.parseNumber(Money.editString(-469.66, "UZS")) ?? 0, -469.66, accuracy: 0.001)
        XCTAssertEqual(Money.editString(10, "USD"), "10")
        XCTAssertEqual(Money.format(1_234_567, "UZS"), "1 234 567 so'm")
    }

    // MARK: Review replies & learning

    func testReplySetsCategoryAndNote() {
        let t = FinanceEngine.addTransaction(kind: .expense, amount: 25_000, currency: "UZS", accountID: card.id,
                                             category: "Boshqa xarajat", merchant: "Evos Chilonzor", ctx: ctx)
        t.needsReview = true
        ReviewHandler.applyReply("Kafe — tushlik do'stlar bilan", to: t, ctx: ctx)
        XCTAssertEqual(t.categoryName, "Kafe va restoran")
        XCTAssertEqual(t.note, "tushlik do'stlar bilan")
        XCTAssertFalse(t.needsReview)
        XCTAssertEqual(FinanceEngine.guessCategory(text: "Evos Chilonzor", kind: .expense, ctx: ctx), "Kafe va restoran")
    }

    func testPlainCommentKeepsCategory() {
        let t = FinanceEngine.addTransaction(kind: .expense, amount: 5_000, currency: "UZS", accountID: card.id,
                                             category: "Transport", merchant: "Yandex Go", ctx: ctx)
        ReviewHandler.applyReply("ishga borish", to: t, ctx: ctx)
        XCTAssertEqual(t.categoryName, "Transport")
        XCTAssertEqual(t.note, "ishga borish")
    }

    func testDoesNotLearnAppNames() {
        let t = FinanceEngine.addTransaction(kind: .expense, amount: 5_000, currency: "UZS", accountID: card.id,
                                             category: "Boshqa xarajat", merchant: "Payme", ctx: ctx)
        ReviewHandler.setCategory("Kommunal", for: t, ctx: ctx)
        XCTAssertNotEqual(FinanceEngine.guessCategory(text: "Payme Beeline", kind: .expense, ctx: ctx), "Kommunal")
    }

    func testPhoneNumberIsLearned() {
        let t = FinanceEngine.addTransaction(kind: .expense, amount: 50_000, currency: "UZS", accountID: card.id,
                                             category: "Boshqa xarajat", merchant: "+998 90 123 45 67", ctx: ctx)
        ReviewHandler.setCategory(SeedData.personalCategory, for: t, ctx: ctx)
        XCTAssertEqual(FinanceEngine.guessCategory(text: "P2P +998901234567", kind: .expense, ctx: ctx), SeedData.personalCategory)
    }

    // MARK: Receipts

    func testReceiptPageParsing() {
        let url = "https://ofd.soliq.uz/check?t=UZ170703100597&r=2421&c=20230104121801&s=514343190161"
        let text = """
        "KORZINKA" MChJ
        STIR: 123456789
        Chek № 2421
        Coca-Cola 1.5L\t1\t12 000.00\t12 000.00
        Non\t2\t3 000.00\t6 000.00
        Jami to'lov:\t18 000.00
        QQS 12%:\t1 928.57
        """
        let info = ReceiptParser.parse(text: text, url: url)
        XCTAssertEqual(info.total, 18_000)
        XCTAssertTrue(info.store.contains("KORZINKA"))
        XCTAssertEqual(info.items, ["Coca-Cola 1.5L", "Non"])
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        let d = cal.dateComponents([.year, .month, .day, .hour, .minute], from: info.date!)
        XCTAssertEqual([d.year, d.month, d.day, d.hour, d.minute], [2023, 1, 4, 12, 18])
        XCTAssertTrue(ReceiptParser.isReceiptURL(url))
        XCTAssertFalse(ReceiptParser.isReceiptURL("https://example.com/check?t=1"))
    }

    func testReceiptMatchesBankPayment() {
        FinanceEngine.addTransaction(kind: .expense, amount: 18_000, currency: "UZS", accountID: card.id,
                                     merchant: "", source: .notification, rawText: "[TBC UZ] Pul yechish 18,000.00 UZS", ctx: ctx)
        XCTAssertNotNil(FinanceEngine.receiptMatch(amount: 18_000, date: Date(), ctx: ctx))
        XCTAssertNil(FinanceEngine.receiptMatch(amount: 19_000, date: Date(), ctx: ctx))
    }

    // MARK: Backup

    func testBackupRestoreKeepsVaultAndEscapesCSV() throws {
        FinanceEngine.addTransaction(kind: .expense, amount: 1_000, currency: "UZS", accountID: card.id,
                                     merchant: "=HYPERLINK(\"http://x\")", ctx: ctx)
        ctx.insert(VaultItem(kind: "passport", payload: Data([1, 2, 3])))
        try ctx.save()

        let csv = try String(contentsOf: BackupManager.exportCSV(ctx), encoding: .utf8)
        XCTAssertTrue(csv.contains("\"'=HYPERLINK"), csv)

        let url = try BackupManager.exportJSON(ctx)
        let n = try BackupManager.importJSON(from: url, ctx: ctx)
        XCTAssertEqual(n, 1)
        XCTAssertEqual((try? ctx.fetch(FetchDescriptor<VaultItem>()))?.count, 1)
        XCTAssertEqual(FinanceEngine.accounts(ctx).count, 2)
        XCTAssertEqual(FinanceEngine.accounts(ctx).first { $0.cardLast4 == "7758" }?.balance ?? 0, 999_000, accuracy: 0.01)
    }

    // MARK: PIN

    func testPasscodeVerifyAndLockout() {
        PasscodeStore.clear()
        PasscodeStore.set("482915")
        XCTAssertTrue(PasscodeStore.isSet)
        if case .success = PasscodeStore.verify("482915") {} else { XCTFail("to'g'ri PIN qabul qilinmadi") }
        for _ in 0..<4 {
            if case .failure = PasscodeStore.verify("000000") {} else { XCTFail("noto'g'ri PIN qabul qilindi") }
        }
        if case .lockedOut = PasscodeStore.verify("000000") {} else { XCTFail("5-xatodan keyin bloklanmadi") }
        if case .lockedOut = PasscodeStore.verify("482915") {} else { XCTFail("bloklangan paytda to'g'ri PIN ham o'tmasligi kerak") }
        PasscodeStore.clear()
        XCTAssertFalse(PasscodeStore.isSet)
    }
}
