import SwiftUI
import SwiftData

@main
struct MyFinApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearance") private var appearance = "dark"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(RateStore.shared)
                .environment(AppLock.shared)
                .environment(AppRouter.shared)
                .environment(VaultSession.shared)
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
    @Environment(AppRouter.self) private var router
    @State private var overlay = OverlayState.shared

    private var overlayVisible: Bool {
        overlay.showSplash || (onboarded && pinSet && lock.isLocked) || overlay.privacy
    }

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
        }
        .animation(.smooth, value: onboarded)
        .onChange(of: overlayVisible, initial: true) { _, visible in
            OverlayWindow.shared.setVisible(visible)
        }
        .task {
            SeedData.seedIfNeeded(context)
            pinSet = PasscodeStore.isSet
            Notifier.registerReviewCategories(context)
            try? await Task.sleep(for: .milliseconds(1600))
            overlay.showSplash = false
            await rates.refreshIfStale()
            WidgetSync.refresh(context)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.didEnterBackground()
                VaultSession.shared.lock()
                WidgetSync.refresh(context)
            case .active:
                lock.didBecomeActive()
            default:
                break
            }
            overlay.privacy = onboarded && !lock.isLocked && phase != .active
        }
        .onChange(of: lock.isLocked) { _, locked in
            if !locked { overlay.privacy = false }
        }
        .onOpenURL { router.handle($0) }
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
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .home
    @State private var addKind: TxKind?
    @State private var openTx: FinTransaction?
    @State private var showVault = false
    @State private var capture: CaptureMode?
    @State private var pendingPrefill: TxPrefill?
    @State private var prefillTx: TxPrefill?

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
            HStack(spacing: 0) {
                Button {
                    Haptics.soft()
                    addKind = .expense
                } label: {
                    Label("Operatsiya qo'shish", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .symbolEffect(.bounce, value: addKind)
                        .frame(maxWidth: .infinity)
                }
                Divider().frame(height: 18)
                Button {
                    Haptics.soft()
                    capture = .scan
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.body.weight(.semibold))
                        .frame(width: 44)
                }
                .accessibilityLabel("Chekni skanerlash")
                Button {
                    Haptics.soft()
                    capture = .photo
                } label: {
                    Image(systemName: "text.viewfinder")
                        .font(.body.weight(.semibold))
                        .frame(width: 44)
                }
                .accessibilityLabel("Skrinshotdan qo'shish")
            }
        }
        .sheet(item: $addKind) { kind in
            TransactionEditor(presetKind: kind)
        }
        .sheet(item: $openTx) { tx in
            TransactionEditor(existing: tx)
        }
        .sheet(isPresented: $showVault) {
            NavigationStack { VaultView() }
        }
        .sheet(item: $capture, onDismiss: {
            if let p = pendingPrefill {
                pendingPrefill = nil
                prefillTx = p
            }
        }) { mode in
            CaptureSheet(mode: mode) { pendingPrefill = $0 }
        }
        .sheet(item: $prefillTx) { p in
            TransactionEditor(prefill: p)
        }
        .onChange(of: router.capture, initial: true) { _, m in
            guard let m else { return }
            router.capture = nil
            capture = m
        }
        .onChange(of: router.addKind, initial: true) { _, k in
            guard let k else { return }
            router.addKind = nil
            addKind = k
        }
        .onChange(of: router.openTransactionID, initial: true) { _, id in
            guard let id else { return }
            router.openTransactionID = nil
            openTx = ReviewHandler.transaction(id, ctx: context)
        }
        .onChange(of: router.openVault, initial: true) { _, v in
            guard v else { return }
            router.openVault = false
            showVault = true
        }
    }
}
