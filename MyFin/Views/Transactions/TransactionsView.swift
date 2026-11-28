import SwiftUI
import SwiftData

struct TransactionRow: View {
    let transaction: FinTransaction
    let accounts: [Account]
    let categories: [FinCategory]
    var showDate: Bool = true

    private var category: FinCategory? {
        categories.first { $0.name == transaction.categoryName }
    }

    private var accountName: String {
        let from = accounts.first { $0.id == transaction.accountID }?.displayName ?? "—"
        if transaction.kind == .transfer {
            let to = accounts.first { $0.id == transaction.toAccountID }?.displayName ?? "—"
            return "\(from) → \(to)"
        }
        return from
    }

    private var icon: String {
        transaction.kind == .transfer ? TxKind.transfer.icon : (category?.icon ?? transaction.kind.icon)
    }

    private var color: Color {
        transaction.kind == .transfer ? Palette.transfer : Color(hex: category?.colorHex ?? "#94A3B8")
    }

    private var signedAmount: Double {
        switch transaction.kind {
        case .expense: return -transaction.amount
        case .income: return transaction.amount
        case .transfer: return transaction.amount
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(icon: icon, color: color, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if transaction.source != .manual {
                        Image(systemName: transaction.source.icon)
                            .font(.caption2)
                    }
                    if transaction.provisional {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.caption2)
                            .foregroundStyle(Palette.warning)
                            .accessibilityLabel("Bank tasdiqlamagan")
                    }
                    Text(showDate ? "\(accountName) · \(transaction.date.uzShort)" : accountName)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            AmountText(value: signedAmount, currency: transaction.currency, font: .subheadline.weight(.bold),
                       signed: transaction.kind != .transfer,
                       color: transaction.kind == .transfer ? Color.primary : transaction.kind.color)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

struct TransactionsView: View {
    @Query(sort: \FinTransaction.date, order: .reverse) private var transactions: [FinTransaction]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \FinCategory.sortOrder) private var categories: [FinCategory]
    @Environment(\.modelContext) private var context
    @Environment(RateStore.self) private var rates
    @AppStorage("baseCurrency") private var base = "UZS"
    @State private var search = ""
    @State private var filter: TxKind? = nil
    @State private var month = Date()
    @State private var allTime = false
    @State private var editing: FinTransaction?
    @State private var adding = false

    private var filtered: [FinTransaction] {
        let cal = Calendar.current
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        return transactions.filter { t in
            if !allTime && !cal.isDate(t.date, equalTo: month, toGranularity: .month) { return false }
            if let filter, t.kind != filter { return false }
            if q.isEmpty { return true }
            return t.merchant.lowercased().contains(q) || t.note.lowercased().contains(q)
                || t.categoryName.lowercased().contains(q)
        }
    }

    private func groups(_ filtered: [FinTransaction]) -> [(day: Date, items: [FinTransaction])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { (day: $0, items: dict[$0] ?? []) }
    }

    private func totals(_ filtered: [FinTransaction]) -> (income: Double, expense: Double) {
        var inc = 0.0, exp = 0.0
        for t in filtered {
            let v = rates.convert(t.amount, from: t.currency, to: base)
            if t.kind == .income { inc += v }
            if t.kind == .expense { exp += v }
        }
        return (inc, exp)
    }

    var body: some View {
        let filtered = self.filtered
        let groups = self.groups(filtered)
        let totals = self.totals(filtered)
        return NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14, pinnedViews: []) {
                    header(totals: totals, count: filtered.count)
                    if groups.isEmpty {
                        GlassCard {
                            ContentUnavailableView(search.isEmpty ? "Bu davrda operatsiya yo'q" : "Hech narsa topilmadi",
                                                   systemImage: "magnifyingglass")
                        }
                    }
                    ForEach(groups, id: \.day) { group in
                        daySection(group.day, group.items)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .navigationTitle("Operatsiyalar")
            .searchable(text: $search, prompt: "Do'kon, izoh yoki kategoriya")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { TransactionEditor(existing: $0) }
            .sheet(isPresented: $adding) { TransactionEditor() }
        }
    }

    private func header(totals: (income: Double, expense: Double), count: Int) -> some View {
        VStack(spacing: 12) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }
                        .buttonStyle(.glass)
                        .disabled(allTime)
                    Button {
                        withAnimation(.snappy) { allTime.toggle() }
                    } label: {
                        Text(allTime ? "Barcha vaqt" : month.uzMonthYear)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22) }
                        .buttonStyle(.glass)
                        .disabled(allTime)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        chip("Hammasi", selected: filter == nil) { filter = nil }
                        ForEach(TxKind.allCases) { k in
                            chip(k.title, selected: filter == k) { filter = k }
                        }
                    }
                }
            }
            GlassCard(padding: 14) {
                HStack {
                    StatPill(title: "Kirim", value: totals.income, currency: base, color: Palette.income, icon: "arrow.down.left")
                    StatPill(title: "Chiqim", value: totals.expense, currency: base, color: Palette.expense, icon: "arrow.up.right")
                    StatPill(title: "Soni", value: Double(count), currency: "", color: Palette.accent, icon: "number")
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 6)
        }
        .buttonStyle(.glass)
        .tint(selected ? Palette.accent : nil)
    }

    private func daySection(_ day: Date, _ items: [FinTransaction]) -> some View {
        let net = items.reduce(0.0) { sum, t in
            let v = rates.convert(t.amount, from: t.currency, to: base)
            switch t.kind {
            case .income: return sum + v
            case .expense: return sum - v
            case .transfer: return sum
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(day.uzDay).font(.subheadline.weight(.semibold))
                Spacer()
                AmountText(value: net, currency: base, font: .caption.weight(.semibold), signed: true,
                           color: net >= 0 ? Palette.income : Palette.expense)
            }
            .padding(.horizontal, 6)
            GlassCard(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(items) { t in
                        Button { editing = t } label: {
                            TransactionRow(transaction: t, accounts: accounts, categories: categories)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { editing = t } label: { Label("Tahrirlash", systemImage: "pencil") }
                            Button(role: .destructive) {
                                withAnimation { FinanceEngine.delete(t, ctx: context) }
                            } label: { Label("O'chirish", systemImage: "trash") }
                        }
                        if t.id != items.last?.id {
                            Divider().padding(.leading, 60).opacity(0.4)
                        }
                    }
                }
            }
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: delta, to: month) {
            withAnimation(.snappy) { month = d }
        }
    }
}
