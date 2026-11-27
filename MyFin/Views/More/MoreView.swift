import SwiftUI
import SwiftData

struct MoreView: View {
    @Query private var budgets: [Budget]
    @Query private var goals: [Goal]
    @Query private var recurring: [RecurringPayment]
    @Environment(RateStore.self) private var rates
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        tile("Tahlil", "chart.bar.xaxis", "#7C8CFF", "Oylik dinamika") { AnalyticsView() }
                        tile("Limitlar", "gauge.with.dots.needle.67percent", "#F59E0B", "Oylik va haftalik") { BudgetsView() }
                        tile("Maqsadlar", "target", "#8B5CF6", "\(goals.count) ta maqsad") { GoalsView() }
                        tile("Doimiy to'lovlar", "repeat.circle.fill", "#06B6D4", "\(recurring.count) ta to'lov") { RecurringView() }
                        tile("Kategoriyalar", "square.grid.3x3.fill", "#EC4899", "Tahrirlash") { CategoriesView() }
                        tile("Valyuta kurslari", "dollarsign.arrow.circlepath", "#10B981", "USD \(Money.number(rates.rate("USD"), decimals: 0))") { RatesView() }
                    }

                    HStack(spacing: 12) {
                        captureTile("Soliq cheki", "qrcode.viewfinder", "#22C55E", "QR skanerlash", .scan)
                        captureTile("Skrinshot", "text.viewfinder", "#F97316", "Rasmdan o'qish", .photo)
                    }

                    NavigationLink {
                        VaultView()
                    } label: {
                        GlassCard(tint: Color(hex: "#2563EB")) {
                            HStack(spacing: 14) {
                                IconBadge(icon: "lock.doc.fill", color: Color(hex: "#2563EB"), size: 46)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Shaxsiy seyf").font(.headline)
                                    Text("Pasport, ID, karta ma'lumotlari · AES-256 shifrlangan")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AutomationView()
                    } label: {
                        GlassCard(tint: Palette.accent) {
                            HStack(spacing: 14) {
                                IconBadge(icon: "bolt.badge.automatic.fill", color: Palette.accent, size: 46)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Kartalarni avtomatik kuzatish").font(.headline)
                                    Text("TBC, Uzum, Anor, Payme, Paynet, Wallet · jurnal")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        GlassCard {
                            HStack(spacing: 14) {
                                IconBadge(icon: "gearshape.fill", color: Color(hex: "#64748B"), size: 46)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sozlamalar").font(.headline)
                                    Text("Xavfsizlik, valyuta, zaxira nusxa, eksport")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .navigationTitle("Ko'proq")
        }
    }

    private func captureTile(_ title: String, _ icon: String, _ color: String, _ subtitle: String,
                             _ mode: CaptureMode) -> some View {
        Button {
            Haptics.soft()
            router.capture = mode
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                IconBadge(icon: icon, color: Color(hex: color), size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.bold)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }

    private func tile<Destination: View>(_ title: String, _ icon: String, _ color: String, _ subtitle: String,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                IconBadge(icon: icon, color: Color(hex: color), size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.bold)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }
}
