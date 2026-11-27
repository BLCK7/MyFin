import Foundation

struct ParsedSMS: Equatable {
    var amount: Double?
    var currency: String
    var isIncome: Bool
    var last4: String?
    var balance: Double?
    var balanceCurrency: String?
    var merchant: String
}

enum SMSParser {
    static let incomeKeys = [
        "popolnen", "zachislen", "postuplen", "poluchen", "vozvrat", "kirim", "tushdi", "tushum",
        "to'ldir", "toldir", "to‘ldir", "toʻldir", "to’ldir", "hisobga o", "kartaga", "na kartu",
        "credit", "refund", "qaytarildi", "qaytarish", "qabul qil", "received", "keldi", "tushirildi",
        "пополн", "зачисл", "поступл", "получен", "возврат"
    ]

    static let expenseKeys = [
        "pokupka", "oplata", "spisan", "snyat", "debit", "xarid", "to'lov", "tolov", "to‘lov", "toʻlov",
        "to’lov", "yechib", "yechildi", "kartadan", "perevod s", "perevod c", "o'tkazma", "otkazma",
        "o‘tkazma", "oʻtkazma", "purchase", "payment", "withdraw", "to'landi", "tolandi", "to‘landi", "toʻlandi",
        "chiqim", "spent", "debited", "sotib", "yechilgan", "naqdlash",
        "покупк", "оплат", "списан", "снят", "перевод с"
    ]

    static let balanceKeys = [
        "balans", "balance", "ostatok", "qoldiq", "dostupno", "mavjud", "bal:", "ost:",
        "баланс", "остаток", "доступно", "available", "qolgan"
    ]

    static let noiseWords = [
        "pokupka", "oplata", "popolnenie", "popolnenie scheta", "scheta", "perevod", "karta", "card",
        "uzcard", "humo", "humocard", "balans", "ostatok", "qoldiq", "summa", "xarid", "to'lov", "tolov",
        "debit", "online", "onlayn", "spisanie", "zachislenie", "data", "vaqt", "sana", "uzs", "sum",
        "so'm", "som", "mavjud", "dostupno", "kirim", "chiqim", "otkazma", "o'tkazma", "kartadan",
        "kartaga", "na kartu", "s karty", "c karti", "s karti", "operatsiya", "operaciya", "tranzaksiya"
    ]

    private static let currencyPattern = #"(UZS|USD|EUR|RUB|SUM|SO['‘ʻ’`]?M|СУМ|СЎМ|\$|€|₽)"#
    private static let numberPattern = #"(\d{1,3}(?:[   .,']\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)"#

    struct AmountMatch {
        let value: Double
        let currency: String
        let location: Int
        let range: NSRange
        let negative: Bool
        let positive: Bool
    }

    static func normalizeCurrency(_ raw: String) -> String {
        let u = raw.uppercased()
        if u == "$" || u == "USD" { return "USD" }
        if u == "€" || u == "EUR" { return "EUR" }
        if u == "₽" || u == "RUB" { return "RUB" }
        return "UZS"
    }

    static func parseNumber(_ raw: String) -> Double? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for ch in ["\u{00A0}", "\u{202F}", " ", "'", "+"] {
            t = t.replacingOccurrences(of: ch, with: "")
        }
        t = t.replacingOccurrences(of: "−", with: "-")
        let hasComma = t.contains(",")
        let hasDot = t.contains(".")
        if hasComma && hasDot {
            if let lc = t.lastIndex(of: ","), let ld = t.lastIndex(of: ".") {
                if lc > ld {
                    t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                } else {
                    t = t.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if hasComma || hasDot {
            let sep: Character = hasComma ? "," : "."
            let parts = t.split(separator: sep, omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2 && parts[1].count <= 2 {
                t = parts.joined(separator: ".")
            } else {
                t = parts.joined()
            }
        }
        guard let v = Double(t), v.isFinite else { return nil }
        return v
    }

    static func amounts(in text: String) -> [AmountMatch] {
        let ns = text as NSString
        var result: [AmountMatch] = []
        let suffix = "([+\\-−]?)\\s?(?<![\\d])" + numberPattern + "\\s?" + currencyPattern
        let prefix = currencyPattern + "\\s?([+\\-−]?)\\s?" + numberPattern + "(?![\\d])"

        if let re = try? NSRegularExpression(pattern: suffix, options: [.caseInsensitive]) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let sign = ns.substring(with: m.range(at: 1))
                let num = ns.substring(with: m.range(at: 2))
                let cur = ns.substring(with: m.range(at: 3))
                if let v = parseNumber(num) {
                    result.append(AmountMatch(value: v, currency: normalizeCurrency(cur), location: m.range.location,
                                              range: m.range, negative: sign == "-" || sign == "−", positive: sign == "+"))
                }
            }
        }
        if let re = try? NSRegularExpression(pattern: prefix, options: [.caseInsensitive]) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let overlaps = result.contains { NSIntersectionRange($0.range, m.range).length > 0 }
                if overlaps { continue }
                let cur = ns.substring(with: m.range(at: 1))
                let sign = ns.substring(with: m.range(at: 2))
                let num = ns.substring(with: m.range(at: 3))
                if let v = parseNumber(num) {
                    result.append(AmountMatch(value: v, currency: normalizeCurrency(cur), location: m.range.location,
                                              range: m.range, negative: sign == "-" || sign == "−", positive: sign == "+"))
                }
            }
        }
        if result.isEmpty {
            let fallback = "(?:summa|summasi|amount|сумма)[:\\s]*" + numberPattern
            if let re = try? NSRegularExpression(pattern: fallback, options: [.caseInsensitive]) {
                for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    if let v = parseNumber(ns.substring(with: m.range(at: 1))) {
                        result.append(AmountMatch(value: v, currency: "UZS", location: m.range.location,
                                                  range: m.range, negative: false, positive: false))
                    }
                }
            }
        }
        return result.sorted { $0.location < $1.location }
    }

    /// Uzbek mobile number in compact form, e.g. "+998901234567".
    static func phoneCompact(in text: String) -> String? {
        let pattern = #"(?<!\d)\+?998[\s\-]?\(?(\d{2})\)?[\s\-]?(\d{3})[\s\-]?(\d{2})[\s\-]?(\d{2})(?!\d)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
        let ns = text as NSString
        let parts = (1...4).map { ns.substring(with: m.range(at: $0)) }
        return "+998" + parts.joined()
    }

    static func prettyPhone(_ compact: String) -> String {
        let d = Array(compact.filter(\.isNumber))
        guard d.count == 12 else { return compact }
        let s = String(d)
        func sub(_ a: Int, _ b: Int) -> String { String(s[s.index(s.startIndex, offsetBy: a)..<s.index(s.startIndex, offsetBy: b)]) }
        return "+998 \(sub(3, 5)) \(sub(5, 8)) \(sub(8, 10)) \(sub(10, 12))"
    }

    static func last4(in text: String) -> String? {
        let patterns = [
            #"(?:\*+|[xX]{2,}|•+|#)\s?(\d{4})(?!\d)"#,
            #"(?:karta|card|карта|kartasi)[^\d\n]{0,8}(\d{4})(?!\d)"#
        ]
        let ns = text as NSString
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
               let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: m.range(at: 1))
            }
        }
        return nil
    }

    private static func firstIndex(of keys: [String], in lower: String) -> Int? {
        var best: Int? = nil
        for k in keys {
            if let r = lower.range(of: k) {
                let idx = lower.distance(from: lower.startIndex, to: r.lowerBound)
                if best == nil || idx < best! { best = idx }
            }
        }
        return best
    }

    static func merchant(in text: String) -> String {
        var cleaned = text
        let removals = [
            "([+\\-−]?)\\s?" + numberPattern + "\\s?" + currencyPattern,
            currencyPattern + "\\s?" + numberPattern,
            #"(?:\*+|[xX]{2,}|•+|#)\s?\d{4}"#,
            #"\d{1,2}[./-]\d{1,2}[./-]\d{2,4}"#,
            #"\d{1,2}:\d{2}(?::\d{2})?"#,
            #"\b\d{4}\b"#
        ]
        for p in removals {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                cleaned = re.stringByReplacingMatches(in: cleaned, range: NSRange(location: 0, length: (cleaned as NSString).length), withTemplate: ",")
            }
        }
        let segments = cleaned
            .components(separatedBy: CharacterSet(charactersIn: ",;\n|:."))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-*()"))) }
            .filter { !$0.isEmpty }

        for seg in segments {
            let lower = seg.lowercased()
            if noiseWords.contains(lower) { continue }
            if balanceKeys.contains(where: { lower.hasPrefix($0) }) { continue }
            let words = seg.split(separator: " ").map(String.init).filter { w in
                let lw = w.lowercased().trimmingCharacters(in: .punctuationCharacters)
                return !noiseWords.contains(lw) && !balanceKeys.contains(lw)
            }
            let candidate = words.joined(separator: " ")
            let letters = candidate.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            if letters >= 3 && Double(letters) / Double(max(candidate.count, 1)) > 0.5 {
                return String(candidate.prefix(40))
            }
        }
        return ""
    }

    static func parse(_ text: String) -> ParsedSMS? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        let all = amounts(in: trimmed)
        let balanceIdx = firstIndex(of: balanceKeys, in: lower)

        var txAmount: AmountMatch? = nil
        var balAmount: AmountMatch? = nil
        if let b = balanceIdx {
            txAmount = all.first { $0.location < b }
            balAmount = all.first { $0.location >= b }
        } else {
            txAmount = all.first
        }
        guard txAmount != nil || balAmount != nil else { return nil }

        let incomeIdx = firstIndex(of: incomeKeys, in: lower)
        let expenseIdx = firstIndex(of: expenseKeys, in: lower)
        var isIncome: Bool
        switch (incomeIdx, expenseIdx) {
        case let (i?, e?): isIncome = i < e
        case (_?, nil): isIncome = true
        case (nil, _?): isIncome = false
        default: isIncome = txAmount?.positive ?? false
        }
        if let t = txAmount {
            if t.negative { isIncome = false }
            if t.positive { isIncome = true }
        }

        return ParsedSMS(
            amount: txAmount?.value,
            currency: txAmount?.currency ?? balAmount?.currency ?? "UZS",
            isIncome: isIncome,
            last4: last4(in: trimmed),
            balance: balAmount?.value,
            balanceCurrency: balAmount?.currency,
            merchant: merchant(in: trimmed)
        )
    }
}
