import XCTest
@testable import MyFin

final class ParserTests: XCTestCase {
    private func p(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> ParsedSMS {
        guard let r = SMSParser.parse(text) else {
            XCTFail("parse nil: \(text)", file: file, line: line)
            return ParsedSMS(amount: nil, currency: "", isIncome: false, last4: nil, balance: nil, balanceCurrency: nil, merchant: "")
        }
        return r
    }

    func testTBCDebitWithBalance() {
        let r = p("Pul yechish, karta: *7758. 1,000.00 UZS. Balans: 1,530.34 UZS.")
        XCTAssertEqual(r.amount, 1000)
        XCTAssertFalse(r.isIncome)
        XCTAssertEqual(r.last4, "7758")
        XCTAssertEqual(r.balance ?? 0, 1530.34, accuracy: 0.001)
        XCTAssertNil(r.ignoreReason)
        XCTAssertEqual(r.merchant, "")
    }

    func testTBCDescriptiveWithoutCard() {
        let r = p("Siz \"UzMobile\" uchun 1000.00 UZS muvaffaqiyatli to‘lov qildingiz")
        XCTAssertEqual(r.amount, 1000)
        XCTAssertFalse(r.isIncome)
        XCTAssertNil(r.last4)
        XCTAssertNil(r.balance)
        XCTAssertNil(r.ignoreReason)
        XCTAssertEqual(SMSParser.quoted(in: "Siz \"UzMobile\" uchun 1000.00 UZS"), "UzMobile")
    }

    func testTBCTopUp() {
        let r = p("kartangiz to‘ldirildi, karta: *7758. 1,000.00 UZS. Balans: 2,530.34 UZS.")
        XCTAssertTrue(r.isIncome)
        XCTAssertEqual(r.amount, 1000)
        XCTAssertEqual(r.last4, "7758")
    }

    func testUzcardPurchaseLatin() {
        let r = p("Pokupka: KORZINKA TASHKENT, 27.11.26 14:22, karta***1234. summa:25,000.00 UZS, balans:1,234,567.89 UZS")
        XCTAssertEqual(r.amount, 25000)
        XCTAssertFalse(r.isIncome)
        XCTAssertEqual(r.last4, "1234")
        XCTAssertEqual(r.balance ?? 0, 1_234_567.89, accuracy: 0.001)
        XCTAssertNil(r.ignoreReason)
    }

    func testUzcardTopUpAndTransfer() {
        let a = p("Popolnenie scheta: 500,000.00 UZS, karta***1234, Dostupno: 1,734,567.89 UZS")
        XCTAssertTrue(a.isIncome)
        XCTAssertEqual(a.amount, 500_000)
        let b = p("Perevod c karti: 100,000.00 UZS, karta***1234, balans: 900,000.00 UZS")
        XCTAssertFalse(b.isIncome)
        XCTAssertEqual(b.balance, 900_000)
    }

    func testHumoSMS() {
        let r = p("HUMOCARD *9300: oplata 20000.00 UZS; BEELINE; 27.11.26 15:01; Dostupno: 29800.00 UZS")
        XCTAssertEqual(r.amount, 20000)
        XCTAssertFalse(r.isIncome)
        XCTAssertEqual(r.last4, "9300")
        XCTAssertEqual(r.balance, 29800)
    }

    func testHumoRussian() {
        let r = p("HUMO: Списание 45 000,00 UZS. Карта *9300. Остаток: 120 000,00 UZS")
        XCTAssertEqual(r.amount, 45000)
        XCTAssertFalse(r.isIncome)
        XCTAssertEqual(r.last4, "9300")
        XCTAssertEqual(r.balance, 120_000)
    }

    func testUzumPurchase() {
        let r = p("Xarid: 35 000 so'm, Korzinka, karta •4411. Qoldiq: 80 000 so'm")
        XCTAssertEqual(r.amount, 35000)
        XCTAssertFalse(r.isIncome)
        XCTAssertEqual(r.last4, "4411")
        XCTAssertEqual(r.balance, 80000)
    }

    func testPaymePayment() {
        let r = p("Payme: Beeline uchun 20 000 so'm to'landi. Karta: HUMO *9300")
        XCTAssertEqual(r.amount, 20000)
        XCTAssertFalse(r.isIncome)
        XCTAssertEqual(r.last4, "9300")
        XCTAssertNil(r.ignoreReason)
    }

    func testCashbackIsIncome() {
        let r = p("Keshbek tushdi: 2 500 so'm, karta *7758")
        XCTAssertTrue(r.isIncome)
        XCTAssertEqual(r.amount, 2500)
        XCTAssertNil(r.ignoreReason)
    }

    func testPrefixCurrency() {
        let r = p("UZS 25,000.00 at Korzinka, card *7758")
        XCTAssertEqual(r.amount, 25000)
    }

    func testIgnoresOTP() {
        XCTAssertNotNil(p("Kod: 482913. Karta *9300 bilan 50000 UZS to'lovni tasdiqlash. Hech kimga aytmang!").ignoreReason)
        XCTAssertNotNil(p("Код подтверждения 123456 для оплаты 50 000 UZS. Никому не сообщайте").ignoreReason)
    }

    func testIgnoresDeclined() {
        XCTAssertNotNil(p("Operatsiya rad etildi: 30 000 UZS, karta *9300. Mablag' yetarli emas").ignoreReason)
        XCTAssertNotNil(p("Отказ: недостаточно средств. 30 000 UZS *9300").ignoreReason)
    }

    func testIgnoresPromoAndReminders() {
        XCTAssertNotNil(p("Aksiya! Uzum Market'da 100 000 so'mgacha keshbek oling").ignoreReason)
        XCTAssertNotNil(p("Eslatma: kredit bo'yicha to'lov muddati 30.11. Summa 500 000 so'm").ignoreReason)
        XCTAssertNotNil(p("Kredit to'lovi 01.12 da karta *9300 dan yechiladi: 500 000 so'm").ignoreReason)
    }

    func testRealUzumFee() {
        let r = p("5 000 UZS, card *7675, UB P2P VISAUZUM2HUMO FEE. Available: 734,60 UZS")
        XCTAssertEqual(r.amount, 5000)
        XCTAssertEqual(r.last4, "7675")
        XCTAssertEqual(r.balance ?? 0, 734.60, accuracy: 0.001)
        XCTAssertNil(r.ignoreReason)
        XCTAssertTrue(SMSParser.isFee("UB P2P VISAUZUM2HUMO FEE."))
        XCTAssertFalse(SMSParser.isFee("Coffee shop"))
        XCTAssertTrue(SMSParser.hasOperationWord("Payment completed"))
    }

    func testRealUzcardIncomingTransfer() {
        let r = p("Kartaga o'tkazma: TBC VISA SALOM2UZCARD, UZ,27.11.26 19:01,karta ***7169. Miqdor:3000.00 UZS Qoldiq:28431.50 UZS")
        XCTAssertTrue(r.isIncome)
        XCTAssertEqual(r.amount, 3000)
        XCTAssertEqual(r.last4, "7169")
        XCTAssertEqual(r.balance ?? 0, 28431.50, accuracy: 0.001)
        XCTAssertEqual(r.merchant, "Salom → Uzcard")
    }

    func testRealUzcardDebit() {
        let r = p("To'lov: TBC UZCARD2VISA SALOM, UZ,27.11.26 18:58,karta ***7169. Miqdor:3000.00 UZS Qoldiq:25431.50 UZS")
        XCTAssertFalse(r.isIncome)
        XCTAssertEqual(r.amount, 3000)
        XCTAssertEqual(r.currency, "UZS")
        XCTAssertEqual(r.last4, "7169")
        XCTAssertEqual(r.balance ?? 0, 25431.50, accuracy: 0.001)
        XCTAssertNil(r.ignoreReason)
        XCTAssertEqual(r.merchant, "Uzcard → Visa Salom")
    }

    func testTransferCodes() {
        XCTAssertEqual(SMSParser.transferCode(in: "UB P2P VISAUZUM2HUMO FEE."), "Visa Uzum → Humo")
        XCTAssertEqual(SMSParser.transferCode(in: "TBC VISA SALOM2UZCARD, UZ"), "Salom → Uzcard")
        XCTAssertNil(SMSParser.transferCode(in: "UB P2P transfer"))
        XCTAssertNil(SMSParser.transferCode(in: "Coffee2Go Tashkent"))
    }

    func testRealHumoSMS() {
        let r = p("HUMOCARD *9300: oplata 2000.00 UZS; Humo to Visa>Tashken; 26-11-27 18:57;  Dostupno: 62.22 UZS")
        XCTAssertFalse(r.isIncome)
        XCTAssertEqual(r.amount, 2000)
        XCTAssertEqual(r.last4, "9300")
        XCTAssertEqual(r.balance ?? 0, 62.22, accuracy: 0.001)
        XCTAssertEqual(r.merchant, "Humo → Visa")
    }

    func testRealTBCTopUpCardFirst() {
        let r = p("*7758 kartangiz to‘ldirildi: 5,000.00 UZS. Balans: 35,530.34 UZS.")
        XCTAssertTrue(r.isIncome)
        XCTAssertEqual(r.amount, 5000)
        XCTAssertEqual(r.last4, "7758")
        XCTAssertEqual(r.balance ?? 0, 35_530.34, accuracy: 0.001)
        XCTAssertNil(r.ignoreReason)
        XCTAssertEqual(r.merchant, "")
    }

    func testRealOperatorSMSIgnored() {
        XCTAssertNotNil(p("Hisobingiz to'ldirildi. PME_GSM. To'lov = 1000.0 SO'M. Balans = 1001.20 SO'M").ignoreReason)
    }

    func testNegativeBalance() {
        XCTAssertEqual(p("Pul yechish, karta: *7758. 3,000.00 UZS. Balans: -469.66 UZS.").balance ?? 0, -469.66, accuracy: 0.001)
    }

    func testPhoneTopUpOperatorSMSHasNoCard() {
        let r = p("Hisobingiz to'ldirildi. PME_GSM. To'lov = 1000.0 SO'M. Balans = 1001.20 SO'M")
        XCTAssertNil(r.last4)
    }
}
