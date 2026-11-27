import SwiftUI
import SwiftData
import Charts

struct MonthPoint: Identifiable {
    let id = UUID()
    let month: Date
    let label: String
    let kind: String
    let amount: Double
}

struct AnalyticsView: View {
    @Query(sort: \FinTransaction.date, order: .reverse) private var transactions: [FinTransaction]
    @Query(sort: \FinCategory.sortOrder) private var categories: [FinCategory]
    @Environment(RateStore.self) private var rates
    @AppStorage("baseCurrency") private var base = "UZS"
    @State private var months = 6
    @State private var selectedMonth = Date()

    private var monthStarts: [Date] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return (0..<months).reversed().compactMap { cal.date(byAdding: .month, value: -$0, to: start) }
    }

    private var points: [MonthPoint] {
        let cal = Calendar.current
        let f = DateFormats.shortMonth
        var result: [MonthPoint] = []
        for m in monthStarts {
            var inc = 0.0, exp = 0.0
            for t in transactions where cal.isDate(t.date, equalTo: m, toGranularity: .month) {
                let v = rates.convert(t.amount, from: t.currency, to: base)
                if t.kind == .income { inc += v }
                if t.kind == .expense { exp += v }
            }
            let label = f.string(from: m).capitalized
            result.append(MonthPoint(month: m, label: label, kind: "Kirim", amount: inc))
            result.append(MonthPoint(month: m, label: label, kind: "Chiqim", amount: exp))
        }
        return result
    }

    private var slices: [CategorySlice] {
        FinanceEngine.spendingByCategory(transactions: transactions, categories: categories, rates: rates, base: base, month: selectedMonth)
    }

    private var selectedExpense: Double { slices.reduce(0) { $0 + $1.amount } }

    private var dailyAverage: Double {
        let cal = Calendar.current
        let days: Int
        if cal.isDate(selectedMonth, equalTo: Date(), toGranularity: .month) {
            days = cal.component(.day, from: Date())
        } else {
            days = cal.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
        }
        return selectedExpense / Double(max(days, 1))
    }

    private var topMerchants: [(String, Double)] {
        let cal = Calendar.current
        var d: [String: Double] = [:]
        for t in transactions where t.kind == .expense && !t.merchant.isEmpty
            && cal.isDate(t.date, equalTo: selectedMonth, toGranularity: .month) {
            d[t.merchant, default: 0] += rates.convert(t.amount, from: t.currency, to: base)
        }
        return d.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    private var savingsRate: Double? {
        let cal = Calendar.current
        var inc = 0.0, exp = 0.0
        for t in transactions where cal.isDate(t.date, equalTo: selectedMonth, toGranularity: .month) {
            let v = rates.convert(t.amount, from: t.currency, to: base)
            if t.kind == .income { inc += v }
            if t.kind == .expense { exp += v }
        }
        guard inc > 0 else { return nil }
        return (inc - exp) / inc
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Davr", selection: $months) {
                    Text("3 oy").tag(3)
                    Text("6 oy").tag(6)
                    Text("12 oy").tag(12)
                }
                .pickerStyle(.segmented)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Kirim va chiqim").font(.headline)
                        Chart(points) { p in
                            BarMark(x: .value("Oy", p.label), y: .value("Summa", p.amount))
                                .foregroundStyle(by: .value("Turi", p.kind))
                                .position(by: .value("Turi", p.kind))
                                .cornerRadius(5)
                        }
                        .chartForegroundStyleScale(["Kirim": Palette.income, "Chiqim": Palette.expense])
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let v = value.as(Double.self) { Text(Money.compact(v)) }
                                }
                            }
                        }
                        .frame(height: 220)
                    }
                }

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }
                            .buttonStyle(.glass)
                        Text(selectedMonth.uzMonthYear)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .glassEffect(.regular, in: .capsule)
                        Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22) }
                            .buttonStyle(.glass)
                    }
                }

                GlassCard {
                    HStack {
                        StatPill(title: "Chiqim", value: selectedExpense, currency: base, color: Palette.expense, icon: "arrow.up.right")
                        StatPill(title: "Kunlik o'rtacha", value: dailyAverage, currency: base, color: Palette.accent, icon: "calendar")
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Tejash", systemImage: "leaf.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.income)
                            Text(savingsRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                                .font(.subheadline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !slices.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Kategoriyalar bo'yicha").font(.headline)
                            Chart(slices) { s in
                                SectorMark(angle: .value("Summa", s.amount), innerRadius: .ratio(0.6), angularInset: 1.5)
                                    .cornerRadius(4)
                                    .foregroundStyle(Color(hex: s.colorHex))
                            }
                            .frame(height: 200)
                            ForEach(slices) { s in
                                HStack(spacing: 10) {
                                    IconBadge(icon: s.icon, color: Color(hex: s.colorHex), size: 30)
                                    Text(s.name).font(.subheadline)
                                    Spacer()
                                    AmountText(value: s.amount, currency: base, font: .subheadline.weight(.semibold))
                                    Text(selectedExpense > 0 ? "\(Int((s.amount / selectedExpense * 100).rounded()))%" : "")
                                        .font(.caption).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                                }
                            }
                        }
                    }
                }

                if !topMerchants.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Eng ko'p xarajat qilingan joylar").font(.headline)
                            ForEach(topMerchants, id: \.0) { m in
                                HStack {
                                    Text(m.0).font(.subheadline).lineLimit(1)
                                    Spacer()
                                    AmountText(value: m.1, currency: base, font: .subheadline.weight(.semibold))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle("Tahlil")
    }

    private func shift(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) {
            withAnimation(.snappy) { selectedMonth = d }
        }
    }
}
