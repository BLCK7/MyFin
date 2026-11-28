import XCTest
import SwiftData
@testable import MyFin

/// Runs the real automation pipeline against an in-memory store with the owner's card layout:
/// TBC Humo •9300, TBC Visa •7758, Uzum card •4411 and cash.
@MainActor
final class LedgerTests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext!
    private var humo: Account!
    private var visa: Account!
    private var uzum: Account!

    override func setUp() async throws {
        Sandbox.active = true
        container = try ModelContainer(for: DataStore.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        ctx = container.mainContext
        humo = Account(name: "Humo", kind: .card, bank: "TBC", cardLast4: "9300", balance: 50_000, sortOrder: 0)
        visa = Account(name: "Visa", kind: .card, bank: "TBC", cardLast4: "7758", balance: 2_530.34, sortOrder: 1)
        uzum = Account(name: "Uzum karta", kind: .card, bank: "Uzum", cardLast4: "4411", balance: 80_000, sortOrder: 2)
        let cash = Account(name: "Naqd", kind: .cash, balance: 15_000, sortOrder: 3)
        cash.bank = ""
        [humo, visa, uzum, cash].forEach { ctx.insert($0!) }
        try ctx.save()
        UserDefaults.standard.removeObject(forKey: "defaultSMSAccountID")
    }

    override func tearDown() async throws {
        Sandbox.active = false
        container = nil
        ctx = nil
    }

    private func tbc(_ text: String) { _ = FinanceEngine.processNotification(title: "TBC UZ", body: text, app: "TBC UZ", ctx: ctx) }
    private func note(_ app: String, _ text: String) { _ = FinanceEngine.processNotification(title: app, body: text, app: app, ctx: ctx) }
    private var txs: [FinTransaction] { (try? ctx.fetch(FetchDescriptor<FinTransaction>(sortBy: [SortDescriptor(\.date)]))) ?? [] }

    private let descriptive = "Siz \"UzMobile\" uchun 1000.00 UZS muvaffaqiyatli to‘lov qildingiz"
    private func debit(_ balance: String) -> String { "Pul yechish, karta: *7758. 1,000.00 UZS. Balans: \(balance) UZS." }

    func testTBCPairDescriptiveFirst() {
        tbc(descriptive)
        tbc(debit("1,530.34"))
        XCTAssertEqual(txs.count, 1)
        let t = txs[0]
        XCTAssertEqual(t.accountID, visa.id)
        XCTAssertEqual(t.merchant, "UzMobile")
        XCTAssertFalse(t.provisional)
        XCTAssertEqual(visa.balance, 1530.34, accuracy: 0.001)
        XCTAssertEqual(humo.balance, 50_000, accuracy: 0.001)
    }

    func testTBCPairDebitFirst() {
        tbc(debit("1,530.34"))
        tbc(descriptive)
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(txs[0].accountID, visa.id)
        XCTAssertEqual(txs[0].merchant, "UzMobile")
        XCTAssertEqual(humo.balance, 50_000, accuracy: 0.001)
    }

    func testTwoRealPaymentsSameAmountSameApp() {
        tbc(debit("1,530.34"))
        tbc(debit("530.34"))
        XCTAssertEqual(txs.count, 2)
        XCTAssertEqual(visa.balance, 530.34, accuracy: 0.001)
    }

    func testTwoPaymentsInterleaved() {
        tbc(descriptive + " #1")
        tbc(descriptive + " #2")
        tbc(debit("1,530.34"))
        tbc(debit("530.34"))
        XCTAssertEqual(txs.count, 2)
        XCTAssertTrue(txs.allSatisfy { $0.accountID == visa.id && !$0.provisional })
        XCTAssertEqual(humo.balance, 50_000, accuracy: 0.001)
        XCTAssertEqual(visa.balance, 530.34, accuracy: 0.001)
    }

    func testPaymeAndUzumAppThenBankWithFee() {
        note("Payme", "Payme: Beeline uchun 20 000 so'm to'landi. Karta: HUMO *9300")
        note("Uzum Bank", "To'lov 20 000 so'm Beeline")
        tbc("Pul yechish, karta: *9300. 20,200.00 UZS. Balans: 29,800.00 UZS.")
        XCTAssertEqual(txs.count, 1)
        let t = txs[0]
        XCTAssertEqual(t.accountID, humo.id)
        XCTAssertEqual(t.amount, 20_200, accuracy: 0.001)
        XCTAssertFalse(t.provisional)
        XCTAssertEqual(humo.balance, 29_800, accuracy: 0.001)
        XCTAssertEqual(uzum.balance, 80_000, accuracy: 0.001)
    }

    func testApplePayThenBank() {
        _ = FinanceEngine.processApplePay(amountText: "2000", merchant: "Korzinka", card: "TBC Salom Visa", ctx: ctx)
        XCTAssertEqual(txs.count, 1)
        XCTAssertTrue(txs[0].provisional)
        XCTAssertEqual(txs[0].accountID, visa.id)
        tbc("Pul yechish, karta: *7758. 2,000.00 UZS. Balans: 530.34 UZS.")
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(txs[0].merchant, "Korzinka")
        XCTAssertFalse(txs[0].provisional)
        XCTAssertEqual(visa.balance, 530.34, accuracy: 0.001)
        XCTAssertEqual(humo.balance, 50_000, accuracy: 0.001)
    }

    func testOwnTransferBecomesTransfer() {
        tbc("P2P o'tkazma, karta: *9300. 30,000.00 UZS. Balans: 20,000.00 UZS.")
        note("Uzum Bank", "Kartangizga 30 000 so'm tushdi, karta *4411. Qoldiq: 110 000 so'm")
        XCTAssertEqual(txs.count, 1)
        let t = txs[0]
        XCTAssertEqual(t.kind, .transfer)
        XCTAssertEqual(t.accountID, humo.id)
        XCTAssertEqual(t.toAccountID, uzum.id)
        XCTAssertEqual(humo.balance, 20_000, accuracy: 0.001)
        XCTAssertEqual(uzum.balance, 110_000, accuracy: 0.001)
    }

    func testOnlyPaymeStaysProvisional() {
        note("Payme", "Payme: Elektr uchun 5 000 so'm to'landi")
        XCTAssertEqual(txs.count, 1)
        XCTAssertTrue(txs[0].provisional)
    }

    func testDifferentCardsSameAmount() {
        tbc("Pul yechish, karta: *9300. 5,000.00 UZS.")
        note("Uzum Bank", "Xarid: 5 000 so'm, Korzinka, karta •4411")
        XCTAssertEqual(txs.count, 2)
        XCTAssertEqual(Set(txs.compactMap(\.accountID)), [humo.id, uzum.id])
    }

    func testSMSAndAppForSameCardMerge() {
        _ = FinanceEngine.processSMS("HUMOCARD *9300: oplata 20000.00 UZS; BEELINE; Dostupno: 30000.00 UZS", ctx: ctx)
        tbc("Pul yechish, karta: *9300. 20,000.00 UZS. Balans: 30,000.00 UZS.")
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(humo.balance, 30_000, accuracy: 0.001)
    }

    func testHumoBotConfirms() {
        note("Payme", "Payme: Beeline uchun 20 000 so'm to'landi")
        note("HUMO bot", "HUMOCARD *9300: oplata 20000.00 UZS; BEELINE; Dostupno: 30000.00 UZS")
        XCTAssertEqual(txs.count, 1)
        XCTAssertFalse(txs[0].provisional)
        XCTAssertEqual(txs[0].accountID, humo.id)
    }

    func testIgnoredMessagesWriteNothing() {
        tbc("Kod: 482913. Karta *7758 bilan 50000 UZS to'lovni tasdiqlash. Hech kimga aytmang!")
        tbc("Operatsiya rad etildi: 30 000 UZS, karta *7758. Mablag' yetarli emas")
        note("Uzum Bank", "Aksiya! Uzum Market'da 100 000 so'mgacha keshbek oling")
        XCTAssertEqual(txs.count, 0)
        XCTAssertEqual(visa.balance, 2_530.34, accuracy: 0.001)
    }

    func testDuplicateDeliveryIgnored() {
        tbc(debit("1,530.34"))
        tbc(debit("1,530.34"))
        XCTAssertEqual(txs.count, 1)
    }

    func testBalanceMismatchPointsAtDuplicate() {
        // The same expense entered by hand, then reported by the bank: MyFin is 1000 below the bank.
        let manual = FinanceEngine.addTransaction(kind: .expense, amount: 1000, currency: "UZS", accountID: visa.id,
                                                  merchant: "UzMobile", ctx: ctx)
        tbc(debit("1,530.34"))
        XCTAssertEqual(visa.balance, 1530.34, accuracy: 0.001)
        let suspect = FinanceEngine.mismatchSuspect(visa, diff: 1000, ctx: ctx)
        XCTAssertEqual(suspect?.tx.id, manual.id)
        XCTAssertEqual(suspect?.action, "removeDup")
        FinanceEngine.removeDuplicate(txID: manual.id, ctx: ctx)
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(visa.balance, 1530.34, accuracy: 0.001)
    }

    func testSandboxDoesNotTouchRealStore() {
        let steps = Sandbox.parse("""
        [TBC UZ] \(descriptive)
        [TBC UZ] \(debit("1,530.34"))
        """)
        let report = Sandbox.run(steps, copying: ctx)
        XCTAssertEqual(report.steps.count, 2)
        XCTAssertEqual(report.transactions.count, 1)
        XCTAssertEqual(txs.count, 0)
        XCTAssertEqual(visa.balance, 2_530.34, accuracy: 0.001)
    }
}
