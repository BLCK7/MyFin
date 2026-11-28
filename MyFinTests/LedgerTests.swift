import XCTest
import SwiftData
@testable import MyFin

/// Runs the real automation pipeline against an in-memory store with the owner's card layout:
/// TBC Humo •9300, TBC Visa •7758, Uzum Visa •7675, an Uzcard •7169 and cash.
@MainActor
final class LedgerTests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext!
    private var humo: Account!
    private var visa: Account!
    private var uzum: Account!
    private var uzcard: Account!

    override func setUp() async throws {
        Sandbox.active = true
        container = try ModelContainer(for: DataStore.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        ctx = container.mainContext
        humo = Account(name: "Humo", kind: .card, bank: "TBC", cardLast4: "9300", balance: 50_000, sortOrder: 0)
        visa = Account(name: "Visa", kind: .card, bank: "TBC", cardLast4: "7758", balance: 2_530.34, sortOrder: 1)
        uzum = Account(name: "Uzum Visa", kind: .card, bank: "Uzum", cardLast4: "7675", balance: 80_000, sortOrder: 2)
        uzcard = Account(name: "Uzcard", kind: .card, bank: "", cardLast4: "7169", balance: 25_431.50, sortOrder: 3)
        let cash = Account(name: "Naqd", kind: .cash, balance: 15_000, sortOrder: 4)
        [humo, visa, uzum, uzcard, cash].forEach { ctx.insert($0!) }
        SeedData.seedIfNeeded(ctx)
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
        note("Uzum Bank", "Kartangizga 30 000 so'm tushdi, karta *7675. Qoldiq: 110 000 so'm")
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
        note("Uzum Bank", "Xarid: 5 000 so'm, Korzinka, karta •7675")
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

    // MARK: Real messages from the owner's phone (27.11.2026)

    func testUzumFeeNotification() {
        _ = FinanceEngine.processNotification(title: "Payment completed",
                                              body: "5 000 UZS, card *7675, UB P2P VISAUZUM2HUMO FEE. Available: 734,60 UZS",
                                              app: "Uzum Bank", ctx: ctx)
        XCTAssertEqual(txs.count, 1)
        let t = txs[0]
        XCTAssertEqual(t.kind, .expense)
        XCTAssertEqual(t.amount, 5000)
        XCTAssertEqual(t.accountID, uzum.id)
        XCTAssertFalse(t.provisional)
        XCTAssertEqual(t.categoryName, SeedData.feeCategory)
        XCTAssertEqual(uzum.balance, 734.60, accuracy: 0.001)
    }

    func testHumoToVisaOwnTransfer() {
        _ = FinanceEngine.processSMS("HUMOCARD *9300: oplata 2000.00 UZS; Humo to Visa>Tashken; 26-11-27 18:57;  Dostupno: 62.22 UZS", ctx: ctx)
        tbc("Pul yechish, karta: *9300. 2,000.00 UZS. Balans: 62.22 UZS.")
        tbc("kartangiz to‘ldirildi, karta: *7758. 2,000.00 UZS. Balans: 4,530.34 UZS.")
        XCTAssertEqual(txs.count, 1)
        let t = txs[0]
        XCTAssertEqual(t.kind, .transfer)
        XCTAssertEqual(t.accountID, humo.id)
        XCTAssertEqual(t.toAccountID, visa.id)
        XCTAssertEqual(humo.balance, 62.22, accuracy: 0.001)
        XCTAssertEqual(visa.balance, 4530.34, accuracy: 0.001)
    }

    func testVisaToUzcardOwnTransfer() {
        tbc("Pul yechish, karta: *7758. 3,000.00 UZS. Balans: -469.66 UZS.")
        _ = FinanceEngine.processSMS("Kartaga o'tkazma: TBC VISA SALOM2UZCARD, UZ,27.11.26 19:01,karta ***7169. Miqdor:3000.00 UZS Qoldiq:28431.50 UZS", ctx: ctx)
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(txs[0].kind, .transfer)
        XCTAssertEqual(txs[0].accountID, visa.id)
        XCTAssertEqual(txs[0].toAccountID, uzcard.id)
        XCTAssertEqual(uzcard.balance, 28431.50, accuracy: 0.001)
        XCTAssertEqual(visa.balance, -469.66, accuracy: 0.001)
    }

    private let tbcTopUp = "*7758 kartangiz to‘ldirildi: 5,000.00 UZS. Balans: 7,530.34 UZS."

    func testUzcardToVisaTransferBankFirst() {
        _ = FinanceEngine.processSMS("To'lov: TBC UZCARD2VISA SALOM, UZ,28.11.26 12:17,karta ***7169. Miqdor:5000.00 UZS Qoldiq:20431.50 UZS", ctx: ctx)
        _ = FinanceEngine.processNotification(title: "Karta to’ldirildi", body: tbcTopUp, app: "TBC UZ", ctx: ctx)
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(txs[0].kind, .transfer)
        XCTAssertEqual(txs[0].accountID, uzcard.id)
        XCTAssertEqual(txs[0].toAccountID, visa.id)
        XCTAssertEqual(visa.balance, 7530.34, accuracy: 0.001)
        XCTAssertEqual(uzcard.balance, 20431.50, accuracy: 0.001)
    }

    func testUzcardToVisaTransferWithFeeTBCFirst() {
        _ = FinanceEngine.processNotification(title: "Karta to’ldirildi", body: tbcTopUp, app: "TBC UZ", ctx: ctx)
        _ = FinanceEngine.processSMS("To'lov: TBC UZCARD2VISA SALOM, UZ,28.11.26 12:17,karta ***7169. Miqdor:5025.00 UZS Qoldiq:20406.50 UZS", ctx: ctx)
        XCTAssertEqual(txs.count, 1)
        let t = txs[0]
        XCTAssertEqual(t.kind, .transfer)
        XCTAssertEqual(t.accountID, uzcard.id)
        XCTAssertEqual(t.toAccountID, visa.id)
        XCTAssertEqual(t.amount, 5025)
        XCTAssertEqual(t.toAmount, 5000)
        XCTAssertEqual(visa.balance, 7530.34, accuracy: 0.001)
        XCTAssertEqual(uzcard.balance, 20406.50, accuracy: 0.001)
    }

    // The owner's real round trip on 27.11: Uzcard → Visa 3 000 at 18:58, then Visa → Uzcard 3 000 at 19:01.
    private let uzcardOut = "To'lov: TBC UZCARD2VISA SALOM, UZ,27.11.26 18:58,karta ***7169. Miqdor:3000.00 UZS Qoldiq:25431.50 UZS"
    private let uzcardIn = "Kartaga o'tkazma: TBC VISA SALOM2UZCARD, UZ,27.11.26 19:01,karta ***7169. Miqdor:3000.00 UZS Qoldiq:28431.50 UZS"
    private let visaIn = "*7758 kartangiz to‘ldirildi: 3,000.00 UZS. Balans: 5,530.34 UZS."
    private let visaOut = "Pul yechish, karta: *7758. 3,000.00 UZS. Balans: 2,530.34 UZS."

    private func assertRoundTrip(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(txs.count, 2, file: file, line: line)
        XCTAssertTrue(txs.allSatisfy { $0.kind == .transfer }, file: file, line: line)
        let pairs = Set(txs.map { "\($0.accountID?.uuidString ?? "")>\($0.toAccountID?.uuidString ?? "")" })
        XCTAssertEqual(pairs, ["\(uzcard.id.uuidString)>\(visa.id.uuidString)", "\(visa.id.uuidString)>\(uzcard.id.uuidString)"],
                       file: file, line: line)
        XCTAssertEqual(uzcard.balance, 28431.50, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(visa.balance, 2530.34, accuracy: 0.001, file: file, line: line)
    }

    func testRealUzcardVisaRoundTripInOrder() {
        uzcard.balance = 28_431.50
        _ = FinanceEngine.processSMS(uzcardOut, ctx: ctx)
        _ = FinanceEngine.processNotification(title: "Karta to’ldirildi", body: visaIn, app: "TBC UZ", ctx: ctx)
        tbc(visaOut)
        _ = FinanceEngine.processSMS(uzcardIn, ctx: ctx)
        assertRoundTrip()
    }

    func testRealUzcardVisaRoundTripSMSLate() {
        uzcard.balance = 28_431.50
        _ = FinanceEngine.processNotification(title: "Karta to’ldirildi", body: visaIn, app: "TBC UZ", ctx: ctx)
        tbc(visaOut)
        _ = FinanceEngine.processSMS(uzcardOut, ctx: ctx)
        _ = FinanceEngine.processSMS(uzcardIn, ctx: ctx)
        assertRoundTrip()
    }

    func testUnpairedUzcardDebitIsTransferCategory() {
        _ = FinanceEngine.processSMS(uzcardOut, ctx: ctx)
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(txs[0].kind, .expense)
        XCTAssertEqual(txs[0].accountID, uzcard.id)
        XCTAssertEqual(txs[0].merchant, "Uzcard → Visa Salom")
        XCTAssertEqual(txs[0].categoryName, "O'tkazmalar")
        XCTAssertEqual(uzcard.balance, 25431.50, accuracy: 0.001)
    }

    func testOperatorSMSIgnored() {
        let r = FinanceEngine.processSMS("Hisobingiz to'ldirildi. PME_GSM. To'lov = 1000.0 SO'M. Balans = 1001.20 SO'M", ctx: ctx)
        XCTAssertTrue(r.hasPrefix("E'tiborsiz"), r)
        XCTAssertEqual(txs.count, 0)
    }

    func testRealUzMobilePaymentWithOperatorSMS() {
        tbc("Pul yechish, karta: *7758. 1,000.00 UZS. Balans: 1,530.34 UZS.")
        tbc(descriptive)
        _ = FinanceEngine.processSMS("Hisobingiz to'ldirildi. PME_GSM. To'lov = 1000.0 SO'M. Balans = 1001.20 SO'M", ctx: ctx)
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(txs[0].merchant, "UzMobile")
        XCTAssertEqual(visa.balance, 1530.34, accuracy: 0.001)
    }

    func testSandboxDoesNotTouchRealStore() {
        let steps = Sandbox.parse("""
        [TBC UZ] \(descriptive)
        [TBC UZ] \(debit("1,530.34"))
        [Uzum Bank | Payment completed] 5 000 UZS, card *7675, UB P2P VISAUZUM2HUMO FEE. Available: 734,60 UZS
        """)
        let report = Sandbox.run(steps, copying: ctx)
        XCTAssertEqual(report.steps.count, 3)
        XCTAssertEqual(report.transactions.count, 2)
        XCTAssertEqual(txs.count, 0)
        XCTAssertEqual(uzum.balance, 80_000, accuracy: 0.001)
    }

    func testSandboxParsesTitle() {
        let steps = Sandbox.parse("[Uzum Bank | Payment completed] 5 000 UZS, card *7675")
        XCTAssertEqual(steps.first?.app, "Uzum Bank")
        XCTAssertEqual(steps.first?.title, "Payment completed")
    }

}
