import Foundation
import SwiftData
import WebKit
import Vision
import UIKit
import UserNotifications

struct TxPrefill: Identifiable {
    let id = UUID()
    var kind: TxKind = .expense
    var amount: Double?
    var currency: String = "UZS"
    var merchant: String = ""
    var note: String = ""
    var date: Date = Date()
    var category: String = ""
    var accountID: UUID? = nil
    var rawText: String = ""
    var source: TxSource = .manual
}

// MARK: Automation log

struct AutomationEvent: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var source: String
    var app: String
    var input: String
    var result: String
}

enum AutomationLog {
    private static let key = "automationLog"

    static func all() -> [AutomationEvent] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([AutomationEvent].self, from: data) else { return [] }
        return list
    }

    static func add(source: String, app: String, input: String, result: String) {
        var list = all()
        list.insert(AutomationEvent(date: Date(), source: source, app: app,
                                    input: String(input.prefix(600)), result: result), at: 0)
        if list.count > 30 { list = Array(list.prefix(30)) }
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: Fiscal receipt (soliq cheki)

struct ReceiptInfo {
    var url: String
    var date: Date?
    var total: Double?
    var store: String
    var items: [String]
}

enum ReceiptParser {
    static func isReceiptURL(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.hasPrefix("http") && (l.contains("soliq.uz") || l.contains("ofd.uz"))
    }

    static func date(from url: String) -> Date? {
        guard let c = URLComponents(string: url)?.queryItems?.first(where: { $0.name == "c" })?.value,
              c.count >= 12, c.allSatisfy(\.isNumber) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Tashkent")
        if c.count >= 14 {
            f.dateFormat = "yyyyMMddHHmmss"
            return f.date(from: String(c.prefix(14)))
        }
        f.dateFormat = "yyyyMMddHHmm"
        return f.date(from: String(c.prefix(12)))
    }

    static let totalLabels = ["jami to'lov", "jami to‘lov", "jami toʻlov", "jami tolov", "to'lov summasi",
                              "итого к оплате", "к оплате", "итого", "umumiy summa", "jami summa", "jami", "всего", "total"]
    static let skipWords = ["stir", "inn", "инн", "kassir", "кассир", "chek", "чек", "qqs", "ндс", "vat", "manzil", "адрес",
                            "sana", "дата", "fiskal", "фискал", "to'lov", "naqd", "налич", "karta", "карт", "jami", "итог",
                            "soliq", "ofd", "terminal", "smena", "смена", "raqam", "номер", "vaqt", "время", "sotuvchi",
                            "продавец", "bonus", "chegirma", "скидка", "сдача", "qaytim", "http", "www", "rahmat", "спасибо",
                            "fm ", "fp ", "zn", "imzo", "belgi", "nkt", "ккм", "kkm", "telefon", "тел"]
    static let companyMarkers = ["mchj", "мчж", "ооо", "ooo", " xk", "хк", "yatt", "ятт", "llc", "mas'uliyati", "jsc", " aj", " ao"]

    static func numbers(in line: String) -> [Double] {
        guard let re = try? NSRegularExpression(pattern: #"\d[\d  ]*(?:[.,]\d{1,2})?"#) else { return [] }
        let ns = line as NSString
        return re.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap {
            SMSParser.parseNumber(ns.substring(with: $0.range))
        }.filter { $0 > 0 }
    }

    static func looksLikeName(_ line: String) -> Bool {
        let x = line.lowercased()
        guard line.count >= 3 && line.count <= 70 else { return false }
        if skipWords.contains(where: { x.contains($0) }) { return false }
        let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return Double(letters) / Double(max(line.count, 1)) > 0.55
    }

    static func parse(text: String, url: String) -> ReceiptInfo {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var total: Double? = nil
        var totalIndex: Int? = nil
        outer: for label in totalLabels {
            for (i, l) in lines.enumerated() {
                let low = l.lowercased()
                guard low.contains(label), !low.contains("qqs"), !low.contains("ндс"), !low.contains("vat") else { continue }
                if let v = numbers(in: l).last, v >= 100 {
                    total = v; totalIndex = i; break outer
                }
                if i + 1 < lines.count, let v = numbers(in: lines[i + 1]).first, v >= 100 {
                    total = v; totalIndex = i; break outer
                }
            }
        }
        if total == nil {
            let candidates = lines.filter { l in
                let low = l.lowercased()
                return !["stir", "inn", "инн", "fm", "fp", "terminal", "raqam", "номер", "telefon", "+998"].contains { low.contains($0) }
            }.flatMap { numbers(in: $0) }.filter { $0 >= 100 && $0 < 100_000_000 }
            total = candidates.max()
        }

        var store = lines.first { l in
            let low = " " + l.lowercased()
            return companyMarkers.contains { low.contains($0) } && l.count <= 80
        } ?? ""
        if store.isEmpty { store = lines.first(where: looksLikeName) ?? "" }

        let end = totalIndex ?? lines.count
        var items: [String] = []
        for line in lines.prefix(end) {
            let cells = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard let first = cells.first, first != store, looksLikeName(first) else { continue }
            if cells.count == 1 && line.count > 60 { continue }
            if !items.contains(first) { items.append(first) }
            if items.count >= 8 { break }
        }

        return ReceiptInfo(url: url, date: date(from: url), total: total,
                           store: String(store.prefix(50)), items: items)
    }
}

/// Loads the electronic receipt page in an off-screen web view (works for both server-rendered and
/// script-rendered pages) and returns the visible text.
@MainActor
final class ReceiptFetcher: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var finished = false

    func fetchText(_ url: URL) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            continuation = cont
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            let wv = WKWebView(frame: CGRect(x: -2000, y: 0, width: 390, height: 900), configuration: config)
            wv.navigationDelegate = self
            wv.isUserInteractionEnabled = false
            wv.alpha = 0.01
            webView = wv
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first?.windows.first
            window?.addSubview(wv)
            wv.load(URLRequest(url: url, timeoutInterval: 20))
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(25))
                self.finish(nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            var text: String? = nil
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(700))
                let value = try? await webView.evaluateJavaScript("document.body ? document.body.innerText : ''")
                if let s = value as? String, s.count > 40 {
                    text = s
                    if !ReceiptParser.numbers(in: s).isEmpty { break }
                }
            }
            self.finish(text)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    private func finish(_ text: String?) {
        guard !finished, let c = continuation else { return }
        finished = true
        continuation = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        c.resume(returning: text)
    }
}

// MARK: Reading screenshots / photos

enum ImageReader {
    struct Result: Sendable {
        var text: String
        var codes: [String]
    }

    static func read(_ data: Data) async -> Result {
        await Task.detached(priority: .userInitiated) {
            guard let img = UIImage(data: data), let cg = img.cgImage else { return Result(text: "", codes: []) }
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = false
            textRequest.recognitionLanguages = ["ru-RU", "en-US"]
            let codeRequest = VNDetectBarcodesRequest()
            codeRequest.symbologies = [.qr]
            try? handler.perform([textRequest, codeRequest])
            let lines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let codes = (codeRequest.results ?? []).compactMap { $0.payloadStringValue }
            return Result(text: lines.joined(separator: "\n"), codes: codes)
        }.value
    }
}

// MARK: Engine helpers

extension FinanceEngine {
    static func receiptAlreadyScanned(_ url: String, ctx: ModelContext) -> FinTransaction? {
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        return txs.first { $0.rawText.contains(url) }
    }

    /// An expense from SMS / notification / Apple Pay that is most likely the same purchase as this receipt.
    static func receiptMatch(amount: Double, date: Date, ctx: ModelContext) -> FinTransaction? {
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        return txs.prefix(200).first { t in
            guard t.kind == .expense, t.source != .receipt, !t.rawText.contains("soliq.uz") else { return false }
            guard abs(t.date.timeIntervalSince(date)) <= 3 * 3600 else { return false }
            let v = RateStore.shared.convert(t.amount, from: t.currency, to: "UZS")
            return abs(v - amount) <= max(1, amount * 0.005)
        }
    }

    static func enrich(_ tx: FinTransaction, with info: ReceiptInfo, ctx: ModelContext) {
        if !info.store.isEmpty { tx.merchant = info.store }
        let items = info.items.joined(separator: ", ")
        if !items.isEmpty {
            tx.note = tx.note.isEmpty ? items : tx.note + " · " + items
        }
        tx.rawText = (tx.rawText.isEmpty ? "" : tx.rawText + "\n") + "QR: " + info.url
        if tx.categoryName == "Boshqa xarajat" || tx.categoryName.isEmpty {
            tx.categoryName = guessCategory(text: info.store + " " + items, kind: .expense, ctx: ctx)
        }
        tx.needsReview = false
        try? ctx.save()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["review-\(tx.id.uuidString)"])
        WidgetSync.schedule(ctx)
    }

    static func prefill(from info: ReceiptInfo, ctx: ModelContext) -> TxPrefill {
        var p = TxPrefill()
        p.kind = .expense
        p.amount = info.total
        p.currency = "UZS"
        p.merchant = info.store
        p.note = String(info.items.joined(separator: ", ").prefix(240))
        p.date = info.date ?? Date()
        p.category = guessCategory(text: info.store + " " + info.items.joined(separator: " "), kind: .expense, ctx: ctx)
        p.accountID = defaultAutomationAccount(ctx)?.id
        p.rawText = "QR: " + info.url
        p.source = .receipt
        return p
    }

    static func prefill(fromText text: String, ctx: ModelContext) -> TxPrefill? {
        guard let parsed = SMSParser.parse(text), let amount = parsed.amount, amount > 0 else { return nil }
        var p = TxPrefill()
        p.kind = parsed.isIncome ? .income : .expense
        p.amount = amount
        p.currency = parsed.currency
        var merchant = parsed.merchant
        if let phone = SMSParser.phoneCompact(in: text) {
            let pretty = SMSParser.prettyPhone(phone)
            merchant = merchant.isEmpty ? pretty : "\(merchant) \(pretty)"
        }
        p.merchant = merchant
        p.category = guessCategory(text: merchant + " " + text, kind: p.kind, ctx: ctx)
        p.accountID = accountFor(last4: parsed.last4, hint: text, ctx: ctx)?.id
        p.rawText = String(text.prefix(600))
        p.source = .screenshot
        return p
    }

    /// Card by last 4 digits, otherwise by the bank name in the text ("TBC", "Uzum"…).
    static func accountFor(last4: String?, hint: String, ctx: ModelContext) -> Account? {
        let all = accounts(ctx).filter { !$0.isArchived }
        if let last4, let a = all.first(where: { $0.cardLast4 == last4 }) { return a }
        if let bank = knownBank(in: hint),
           let a = all.first(where: { $0.bank.lowercased().contains(bank.key) || $0.name.lowercased().contains(bank.key) }) {
            return a
        }
        return defaultAutomationAccount(ctx)
    }
}
