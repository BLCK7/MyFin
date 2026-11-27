import WidgetKit
import SwiftUI

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .placeholder : (WidgetSnapshot.load() ?? .placeholder)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

private func money(_ v: Double, _ c: String, _ hide: Bool, compact: Bool = false) -> String {
    if hide { return "••••••" }
    return compact ? Money.compactFormat(v, c) : Money.format(v, c)
}

private struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: "#141A3A"), Color(hex: "#2A1B5E"), Color(hex: "#0E3550")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct BrandRow: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.pie.fill").font(.caption2)
            Text("SAMINOV").font(.system(size: 10, weight: .black, design: .rounded)).tracking(1)
            Text("’s financer").font(.system(size: 9, weight: .semibold, design: .rounded)).opacity(0.7)
        }
        .foregroundStyle(Color(hex: "#C7D2FE"))
    }
}

struct BalanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var s: WidgetSnapshot { entry.snapshot ?? .placeholder }

    var body: some View {
        if entry.snapshot == nil {
            VStack(alignment: .leading, spacing: 6) {
                BrandRow()
                Spacer(minLength: 0)
                Text("MyFin'ni bir marta oching").font(.caption.weight(.semibold)).foregroundStyle(.white)
                Text("Vidjet ma'lumotlari ilova ochilganda yangilanadi.").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(URL(string: "myfin://open"))
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall: small
        case .systemMedium: medium
        case .systemLarge: large
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            BrandRow()
            Spacer(minLength: 0)
            Text("Hisoblarda").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            Text(money(s.totalBalance, s.base, s.hide, compact: true))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .privacySensitive()
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right").font(.caption2.bold())
                Text("Bugun \(money(s.todayExpense, s.base, s.hide, compact: true))")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .privacySensitive()
            }
            .foregroundStyle(Palette.expense)
            if s.pendingReview > 0 {
                Label("\(s.pendingReview) ta izohsiz", systemImage: "text.bubble.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.warning)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "myfin://add?kind=expense"))
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                BrandRow()
                Spacer(minLength: 0)
                Text("Sof boylik").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                Text(money(s.netWorth, s.base, s.hide, compact: true))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .privacySensitive()
                HStack(spacing: 10) {
                    stat("arrow.down.left", s.monthIncome, Palette.income)
                    stat("arrow.up.right", s.monthExpense, Palette.expense)
                }
                HStack(spacing: 6) {
                    Link(destination: URL(string: "myfin://add?kind=expense")!) { pill("minus", "Chiqim", Palette.expense) }
                    Link(destination: URL(string: "myfin://add?kind=income")!) { pill("plus", "Kirim", Palette.income) }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(s.accounts.prefix(3)) { a in accountRow(a) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BrandRow()
                Spacer()
                Link(destination: URL(string: "myfin://add?kind=expense")!) { pill("plus", "Qo'shish", Palette.accent) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Sof boylik").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                Text(money(s.netWorth, s.base, s.hide))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .privacySensitive()
            }
            HStack(spacing: 14) {
                stat("arrow.down.left", s.monthIncome, Palette.income)
                stat("arrow.up.right", s.monthExpense, Palette.expense)
                if s.budgetLimit > 0 {
                    Gauge(value: min(1, s.monthExpense / s.budgetLimit)) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(s.monthExpense > s.budgetLimit ? Palette.expense : Palette.warning)
                }
            }
            Divider().overlay(Color.white.opacity(0.2))
            ForEach(s.accounts.prefix(3)) { a in accountRow(a) }
            Divider().overlay(Color.white.opacity(0.2))
            ForEach(s.recent.prefix(4)) { t in txRow(t) }
            Spacer(minLength: 0)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "chart.pie.fill")
                Text("MyFin").font(.headline)
            }
            Text(money(s.totalBalance, s.base, s.hide, compact: true))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .privacySensitive()
            Text("Bugun: −\(money(s.todayExpense, s.base, s.hide, compact: true))")
                .font(.caption)
                .privacySensitive()
        }
        .widgetURL(URL(string: "myfin://add?kind=expense"))
    }

    private var circular: some View {
        Gauge(value: s.budgetLimit > 0 ? min(1, s.monthExpense / s.budgetLimit) : 0) {
            Image(systemName: "chart.pie.fill")
        } currentValueLabel: {
            Text(s.hide ? "•" : Money.compact(s.monthExpense).replacingOccurrences(of: " mln", with: "M")
                .replacingOccurrences(of: " ming", with: "K"))
                .privacySensitive()
        }
        .gaugeStyle(.accessoryCircular)
        .widgetURL(URL(string: "myfin://add?kind=expense"))
    }

    private var inline: some View {
        Text("💳 \(money(s.totalBalance, s.base, s.hide, compact: true))")
            .privacySensitive()
    }

    private func stat(_ icon: String, _ v: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2.bold())
            Text(money(v, s.base, s.hide, compact: true)).font(.caption2.weight(.semibold)).lineLimit(1)
                .privacySensitive()
        }
        .foregroundStyle(color)
    }

    private func pill(_ icon: String, _ title: String, _ color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.35), in: Capsule())
    }

    private func accountRow(_ a: WidgetSnapshot.Acc) -> some View {
        HStack(spacing: 8) {
            Image(systemName: a.icon)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color(hex: a.colorHex), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 0) {
                Text(a.last4.isEmpty ? a.name : "\(a.name) •\(a.last4)")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                Text(money(a.balance, a.currency, s.hide, compact: true))
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    .privacySensitive()
            }
        }
    }

    private func txRow(_ t: WidgetSnapshot.Tx) -> some View {
        HStack(spacing: 8) {
            Image(systemName: t.icon)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color(hex: t.colorHex), in: RoundedRectangle(cornerRadius: 6))
            Text(t.title).font(.caption.weight(.medium)).foregroundStyle(.white).lineLimit(1)
            Spacer()
            Text((t.isTransfer ? "" : (t.isIncome ? "+" : "−")) + money(t.amount, t.currency, s.hide, compact: true))
                .font(.caption.weight(.bold))
                .foregroundStyle(t.isTransfer ? Color.white : (t.isIncome ? Palette.income : Palette.expense))
                .privacySensitive()
        }
    }
}

struct BalanceWidget: Widget {
    let kind = "MyFinBalanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            BalanceWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("MyFin balans")
        .description("Hisoblar, sof boylik va bugungi xarajatlar.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct QuickAddWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(spacing: 8) {
            BrandRow()
            Spacer(minLength: 0)
            Link(destination: URL(string: "myfin://add?kind=expense")!) {
                Label("Chiqim", systemImage: "minus.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Palette.expense.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            }
            Link(destination: URL(string: "myfin://add?kind=income")!) {
                Label("Kirim", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Palette.income.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .foregroundStyle(.white)
    }
}

struct QuickAddWidget: Widget {
    let kind = "MyFinQuickAddWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            QuickAddWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Tezkor qo'shish")
        .description("Bir bosishda kirim yoki chiqim yozish.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct MyFinWidgets: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
        QuickAddWidget()
    }
}
