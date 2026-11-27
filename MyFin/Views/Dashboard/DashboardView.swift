import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Binding var tab: AppTab
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \FinTransaction.date, order: .reverse) private var transactions: [FinTransaction]
    @Query private var debts: [Debt]
    @Query private var budgets: [Budget]
    @Query(sort: \FinCategory.sortOrder) private var categories: [FinCategory]
    @Environment(RateStore.self) private var rates
    @AppStorage("baseCurrency") private var base = "UZS"
    @AppStorage("userName") private var userName = ""
    @AppStorage("hideAmounts") private var hide = false
    @State private var editing: FinTransaction?

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    private var summary: FinanceSummary {
        FinanceEngine.summary(accounts: accounts, transactions: transactions, debts: debts, rates: rates, base: base)
    }

    private var slices: [CategorySlice] {
        FinanceEngine.spendingByCategory(transactions: transactions, categories: categories, rates: rates, base: base, month: Date())
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 5 ? "Xayrli tun" : (h < 12 ? "Xayrli tong" : (h < 18 ? "Xayrli kun" : "Xayrli kech"))
        return userName.isEmpty ? part : "\(part), \(userName)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    NetWorthCard(summary: summary, base: base)
                    MonthCard(summary: summary, base: base)
                    AccountsStrip(accounts: activeAccounts) { tab = .accounts }
                    if !slices.isEmpty {
                        SpendingCard(slices: slices, base: base, total: summary.monthExpense)
                    }
                    if !budgets.isEmpty {
                        BudgetPreview(budgets: budgets, transactions: transactions, categories: categories, base: base)
                    }
                    UpcomingDebtsCard(debts: debts) { tab = .debts }
                    RecentCard(transactions: Array(transactions.prefix(6)), accounts: accounts, categories: categories,
                               onSelect: { editing = $0 }, onAll: { tab = .transactions })
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .navigationTitle(greeting)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) { hide.toggle() }
                    } label: {
                        Image(systemName: hide ? "eye.slash.fill" : "eye.fill")
                    }
                    .accessibilityLabel(hide ? "Summalarni ko'rsatish" : "Summalarni yashirish")
                }
            }
            .refreshable { await rates.refresh() }
            .sheet(item: $editing) { tx in
                TransactionEditor(existing: tx)
            }
        }
    }
}

private struct NetWorthCard: View {
    let summary: FinanceSummary
    let base: String

    var body: some View {
        GlassCard(padding: 20, radius: 30, tint: Palette.accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Sof boylik", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Date().uzMonthYear)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                AmountText(value: summary.netWorth, currency: base, font: .system(size: 38, weight: .bold, design: .rounded))
                Divider().opacity(0.4)
                HStack(spacing: 12) {
                    StatPill(title: "Hisoblarda", value: summary.totalAssets, currency: base, color: Palette.accent, icon: "wallet.pass.fill")
                    StatPill(title: "Qarzlarim", value: summary.iOwe, currency: base, color: Palette.expense, icon: "arrow.up.forward")
                    StatPill(title: "Haqlarim", value: summary.owedToMe, currency: base, color: Palette.income, icon: "arrow.down.backward")
                }
            }
        }
    }
}

private struct MonthCard: View {
    let summary: FinanceSummary
    let base: String

    private var ratio: Double {
        guard summary.monthIncome > 0 else { return summary.monthExpense > 0 ? 1 : 0 }
        return summary.monthExpense / summary.monthIncome
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Shu oy")
                    .font(.headline)
                HStack(spacing: 12) {
                    StatPill(title: "Kirim", value: summary.monthIncome, currency: base, color: Palette.income, icon: "arrow.down.left")
                    StatPill(title: "Chiqim", value: summary.monthExpense, currency: base, color: Palette.expense, icon: "arrow.up.right")
                    StatPill(title: "Farq", value: summary.monthNet, currency: base,
                             color: summary.monthNet >= 0 ? Palette.income : Palette.expense, icon: "equal")
                }
                ProgressCapsule(progress: ratio, color: ratio > 0.9 ? Palette.expense : (ratio > 0.7 ? Palette.warning : Palette.income))
                Text(summary.monthIncome > 0
                     ? "Daromadning \(Int((ratio * 100).rounded()))% qismi sarflandi"
                     : "Bu oy hali kirim yozilmagan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AccountsStrip: View {
    let accounts: [Account]
    let onAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Hisoblar", actionTitle: "Hammasi", action: onAll)
            if accounts.isEmpty {
                GlassCard {
                    Text("Hali hisob qo'shilmagan").foregroundStyle(.secondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(accounts) { a in
                            NavigationLink {
                                AccountDetailView(account: a)
                            } label: {
                                AccountCardView(account: a)
                                    .frame(width: 250, height: 150)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }
}

private struct SpendingCard: View {
    let slices: [CategorySlice]
    let base: String
    let total: Double

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Xarajatlar tarkibi")
                    .font(.headline)
                HStack(spacing: 18) {
                    ZStack {
                        Chart(slices) { s in
                            SectorMark(angle: .value("Summa", s.amount), innerRadius: .ratio(0.64), angularInset: 1.5)
                                .cornerRadius(4)
                                .foregroundStyle(Color(hex: s.colorHex))
                        }
                        .frame(width: 140, height: 140)
                        VStack(spacing: 2) {
                            Text("Jami").font(.caption2).foregroundStyle(.secondary)
                            AmountText(value: total, currency: base, font: .caption.weight(.bold))
                                .frame(width: 84)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(slices.prefix(5)) { s in
                            HStack(spacing: 8) {
                                Circle().fill(Color(hex: s.colorHex)).frame(width: 8, height: 8)
                                Text(s.name).font(.caption).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(total > 0 ? "\(Int((s.amount / total * 100).rounded()))%" : "")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct BudgetPreview: View {
    let budgets: [Budget]
    let transactions: [FinTransaction]
    let categories: [FinCategory]
    let base: String
    @Environment(RateStore.self) private var rates

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Byudjetlar")
            GlassCard {
                VStack(spacing: 14) {
                    ForEach(budgets.prefix(4)) { b in
                        BudgetRow(budget: b,
                                  spent: FinanceEngine.spent(category: b.categoryName, transactions: transactions, rates: rates, base: base),
                                  category: categories.first { $0.name == b.categoryName },
                                  base: base)
                    }
                }
            }
        }
    }
}

private struct UpcomingDebtsCard: View {
    let debts: [Debt]
    let onAll: () -> Void

    private var upcoming: [Debt] {
        debts.filter { !$0.isClosed && $0.dueDate != nil }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Yaqin muddatlar", actionTitle: "Qarzlar", action: onAll)
                GlassCard {
                    VStack(spacing: 12) {
                        ForEach(upcoming.prefix(3)) { d in
                            HStack(spacing: 12) {
                                IconBadge(icon: d.direction.icon, color: d.direction.color, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.person).font(.subheadline.weight(.semibold))
                                    Text(d.isOverdue ? "Muddati o'tgan" : (d.dueDate?.uzDate ?? ""))
                                        .font(.caption)
                                        .foregroundStyle(d.isOverdue ? Palette.expense : .secondary)
                                }
                                Spacer()
                                AmountText(value: d.remaining, currency: d.currency, font: .subheadline.weight(.bold),
                                           color: d.direction.color)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct RecentCard: View {
    let transactions: [FinTransaction]
    let accounts: [Account]
    let categories: [FinCategory]
    let onSelect: (FinTransaction) -> Void
    let onAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "So'nggi operatsiyalar", actionTitle: "Hammasi", action: onAll)
            GlassCard(padding: 8) {
                if transactions.isEmpty {
                    ContentUnavailableView("Operatsiyalar yo'q", systemImage: "tray",
                                           description: Text("Pastdagi “Operatsiya qo'shish” tugmasi orqali birinchisini yozing."))
                } else {
                    VStack(spacing: 0) {
                        ForEach(transactions) { t in
                            Button { onSelect(t) } label: {
                                TransactionRow(transaction: t, accounts: accounts, categories: categories)
                            }
                            .buttonStyle(.plain)
                            if t.id != transactions.last?.id {
                                Divider().padding(.leading, 60).opacity(0.4)
                            }
                        }
                    }
                }
            }
        }
    }
}
