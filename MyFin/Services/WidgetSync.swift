import Foundation
import SwiftData
import WidgetKit

@MainActor
enum WidgetSync {
    private static var pending: Task<Void, Never>?

    static func schedule(_ context: ModelContext? = nil) {
        guard !Sandbox.active else { return }
        let ctx = context ?? DataStore.context
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            refresh(ctx)
        }
    }

    static func refresh(_ context: ModelContext? = nil) {
        let ctx = context ?? DataStore.context
        let defaults = UserDefaults.standard
        let base = defaults.string(forKey: "baseCurrency") ?? "UZS"
        let hide = defaults.bool(forKey: "hideAmounts")
        let rates = RateStore.shared
        let accounts = FinanceEngine.accounts(ctx).filter { !$0.isArchived }
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let debts = (try? ctx.fetch(FetchDescriptor<Debt>())) ?? []
        let budgets = (try? ctx.fetch(FetchDescriptor<Budget>())) ?? []
        let cats = FinanceEngine.categories(ctx)
        let byName = Dictionary(cats.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        let s = FinanceEngine.summary(accounts: accounts, transactions: txs, debts: debts, rates: rates, base: base)
        let cal = Calendar.current
        var todayExp = 0.0, todayInc = 0.0
        for t in txs where cal.isDateInToday(t.date) {
            let v = rates.convert(t.amount, from: t.currency, to: base)
            if t.kind == .expense { todayExp += v }
            if t.kind == .income { todayInc += v }
        }

        let snapshot = WidgetSnapshot(
            updatedAt: Date(), base: base, hide: hide,
            netWorth: s.netWorth, totalBalance: s.totalAssets,
            todayExpense: todayExp, todayIncome: todayInc,
            monthIncome: s.monthIncome, monthExpense: s.monthExpense,
            budgetLimit: budgets.first(where: { $0.isOverall && $0.period == .month })?.limit
                ?? budgets.filter { $0.period == .month }.reduce(0) { $0 + $1.limit },
            pendingReview: txs.filter(\.needsReview).count,
            accounts: accounts.prefix(6).map {
                WidgetSnapshot.Acc(id: $0.id.uuidString, name: $0.name, last4: $0.cardLast4, balance: $0.balance,
                                   currency: $0.currency, colorHex: $0.colorHex, icon: $0.kind.icon)
            },
            recent: txs.prefix(5).map { t in
                let c = byName[t.categoryName]
                return WidgetSnapshot.Tx(id: t.id.uuidString, title: t.title, amount: t.amount, currency: t.currency,
                                         isIncome: t.kind == .income, isTransfer: t.kind == .transfer, date: t.date,
                                         icon: t.kind == .transfer ? "arrow.left.arrow.right" : (c?.icon ?? "tag.fill"),
                                         colorHex: t.kind == .transfer ? "#60A5FA" : (c?.colorHex ?? "#94A3B8"))
            }
        )
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
