import Foundation
import Observation

@Observable
@MainActor
final class RateStore {
    static let shared = RateStore()

    var rates: [String: Double]
    var updatedAt: Date?
    var cbuDate: String = ""
    var isLoading = false
    var lastError: String?

    private let ratesKey = "cbuRates"
    private let dateKey = "cbuRatesUpdatedAt"
    private let cbuDateKey = "cbuRatesDate"

    private init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.dictionary(forKey: ratesKey) as? [String: Double], !saved.isEmpty {
            rates = saved
        } else {
            rates = ["UZS": 1, "USD": 12_100, "EUR": 14_000, "RUB": 150]
        }
        updatedAt = defaults.object(forKey: dateKey) as? Date
        cbuDate = defaults.string(forKey: cbuDateKey) ?? ""
    }

    func rate(_ code: String) -> Double {
        if code == "UZS" { return 1 }
        return rates[code] ?? 1
    }

    func convert(_ amount: Double, from: String, to: String) -> Double {
        if from == to { return amount }
        let r = rate(to)
        guard r > 0 else { return amount }
        return amount * rate(from) / r
    }

    func refreshIfStale() async {
        if let updatedAt, Date().timeIntervalSince(updatedAt) < 6 * 3600 { return }
        await refresh()
    }

    private struct CBUItem: Decodable {
        let code: String
        let rate: String
        let nominal: String?
        let day: String?

        enum CodingKeys: String, CodingKey {
            case code = "Ccy"
            case rate = "Rate"
            case nominal = "Nominal"
            case day = "Date"
        }
    }

    func refresh() async {
        guard let url = URL(string: "https://cbu.uz/uz/arkhiv-kursov-valyut/json/") else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            let items = try JSONDecoder().decode([CBUItem].self, from: data)
            var fresh: [String: Double] = ["UZS": 1]
            for item in items where Currencies.all.contains(item.code) {
                let nominal = Double(item.nominal ?? "1") ?? 1
                if let r = Double(item.rate.replacingOccurrences(of: ",", with: ".")), nominal > 0 {
                    fresh[item.code] = r / nominal
                }
                if let d = item.day { cbuDate = d }
            }
            guard fresh.count > 1 else { return }
            rates = fresh
            updatedAt = Date()
            lastError = nil
            let defaults = UserDefaults.standard
            defaults.set(fresh, forKey: ratesKey)
            defaults.set(updatedAt, forKey: dateKey)
            defaults.set(cbuDate, forKey: cbuDateKey)
        } catch {
            lastError = "Kurslarni yangilab bo'lmadi. Internet aloqasini tekshiring."
        }
    }
}
