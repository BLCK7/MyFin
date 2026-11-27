import SwiftUI
import SwiftData

@main
struct MyFinApp: App {
    @AppStorage("appearance") private var appearance = "dark"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(RateStore.shared)
                .environment(AppLock.shared)
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
    @AppStorage("pinSet") private var pinSet = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Environment(RateStore.self) private var rates
    @Environment(AppLock.self) private var lock
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if !onboarded {
                OnboardingView()
            } else if !pinSet {
                PasscodeSetupView(mode: .create) {
                    withAnimation(.smooth) {
                        pinSet = true
                        lock.unlock()
                    }
                }
            } else {
                MainTabs()
            }

            if onboarded && pinSet && lock.isLocked && !showSplash {
                LockScreen()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(2)
            }

            if onboarded && !lock.isLocked && scenePhase != .active {
                PrivacyCover()
                    .transition(.opacity)
                    .zIndex(3)
            }

            if showSplash {
                SplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
                    .zIndex(4)
            }
        }
        .animation(.smooth(duration: 0.4), value: lock.isLocked)
        .animation(.smooth, value: onboarded)
        .task {
            SeedData.seedIfNeeded(context)
            pinSet = PasscodeStore.isSet
            try? await Task.sleep(for: .milliseconds(1900))
            withAnimation(.smooth(duration: 0.5)) { showSplash = false }
            await rates.refreshIfStale()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: lock.didEnterBackground()
            case .active: lock.didBecomeActive()
            default: break
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
                Haptics.soft()
                showAdd = true
            } label: {
                Label("Operatsiya qo'shish", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .symbolEffect(.bounce, value: showAdd)
                    .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showAdd) {
            TransactionEditor()
        }
    }
}
