import SwiftUI
import SwiftData

@main
struct MyFinApp: App {
    @AppStorage("appearance") private var appearance = "dark"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(RateStore.shared)
                .preferredColorScheme(colorScheme)
                .tint(Palette.accent)
        }
        .modelContainer(DataStore.container)
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "system": return nil
        default: return .dark
        }
    }
}

struct RootView: View {
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Environment(RateStore.self) private var rates
    @State private var locked = true
    @State private var authenticating = false

    var body: some View {
        ZStack {
            if onboarded {
                MainTabs()
            } else {
                OnboardingView()
            }

            if onboarded && faceIDEnabled && locked {
                LockView(authenticating: authenticating) { Task { await unlock() } }
                    .transition(.opacity)
                    .zIndex(2)
            }

            if onboarded && scenePhase != .active && !(faceIDEnabled && locked) {
                PrivacyCover()
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .animation(.smooth, value: locked)
        .animation(.smooth, value: onboarded)
        .task {
            SeedData.seedIfNeeded(context)
            if faceIDEnabled && locked { await unlock() }
            await rates.refreshIfStale()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && faceIDEnabled {
                locked = true
            }
            if phase == .active && faceIDEnabled && locked && !authenticating {
                Task { await unlock() }
            }
        }
    }

    private func unlock() async {
        guard !authenticating else { return }
        authenticating = true
        let ok = await Biometrics.authenticate(reason: "MyFin'ni ochish")
        authenticating = false
        if ok { locked = false }
    }
}

struct LockView: View {
    let authenticating: Bool
    let unlock: () -> Void

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(28)
                    .glassEffect(.regular, in: .circle)
                Text("MyFin qulflangan")
                    .font(.title2.bold())
                Text("Davom etish uchun \(Biometrics.name) bilan tasdiqlang")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: unlock) {
                    Label(authenticating ? "Tekshirilmoqda…" : "Ochish", systemImage: "faceid")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(authenticating)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
    }
}

struct PrivacyCover: View {
    var body: some View {
        ZStack {
            AppBackground()
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 56))
                .foregroundStyle(Palette.accent)
                .padding(30)
                .glassEffect(.regular, in: .circle)
        }
    }
}

struct MainTabs: View {
    @State private var tab: AppTab = .home
    @State private var showAdd = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Asosiy", systemImage: "chart.pie.fill", value: AppTab.home) {
                DashboardView(tab: $tab)
            }
            Tab("Operatsiyalar", systemImage: "list.bullet.rectangle.portrait.fill", value: AppTab.transactions) {
                TransactionsView()
            }
            Tab("Hisoblar", systemImage: "creditcard.fill", value: AppTab.accounts) {
                AccountsView()
            }
            Tab("Qarzlar", systemImage: "person.2.fill", value: AppTab.debts) {
                DebtsView()
            }
            Tab("Ko'proq", systemImage: "square.grid.2x2.fill", value: AppTab.more) {
                MoreView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            Button {
                showAdd = true
            } label: {
                Label("Operatsiya qo'shish", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showAdd) {
            TransactionEditor()
        }
    }
}
