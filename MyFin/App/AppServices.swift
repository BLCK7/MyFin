import SwiftUI
import SwiftData
import UserNotifications
import Observation

@Observable
@MainActor
final class AppRouter {
    static let shared = AppRouter()
    var addKind: TxKind?
    var openTransactionID: UUID?
    var openVault = false
    var capture: CaptureMode?
    private init() {}

    func handle(_ url: URL) {
        guard url.scheme == "myfin" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host {
        case "add":
            addKind = TxKind(rawValue: value("kind") ?? "expense") ?? .expense
        case "tx":
            if let id = value("id").flatMap(UUID.init(uuidString:)) { openTransactionID = id }
        case "vault":
            openVault = true
        case "scan":
            capture = value("mode") == "photo" ? .photo : .scan
        default:
            break
        }
    }
}

@Observable
@MainActor
final class OverlayState {
    static let shared = OverlayState()
    var showSplash = true
    var privacy = false
    private init() {}
}

@MainActor
enum ReviewHandler {
    static func transaction(_ id: UUID, ctx: ModelContext) -> FinTransaction? {
        let txs = (try? ctx.fetch(FetchDescriptor<FinTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        return txs.first { $0.id == id }
    }

    static func handle(txID: UUID, action: String, text: String?) {
        let ctx = DataStore.context
        guard let tx = transaction(txID, ctx: ctx) else { return }
        if action == "comment", let text {
            applyReply(text, to: tx, ctx: ctx)
        } else if action.hasPrefix("cat:") {
            setCategory(String(action.dropFirst(4)), for: tx, ctx: ctx)
            tx.needsReview = false
        } else if action == UNNotificationDefaultActionIdentifier || action == "open" {
            AppRouter.shared.openTransactionID = txID
            return
        } else {
            return
        }
        try? ctx.save()
        WidgetSync.schedule(ctx)
    }

    static func setCategory(_ name: String, for tx: FinTransaction, ctx: ModelContext) {
        guard !name.isEmpty else { return }
        tx.categoryName = name
        FinanceEngine.learn(category: name, from: tx, ctx: ctx)
        if tx.kind == .expense { FinanceEngine.checkBudget(category: name, ctx: ctx) }
    }

    /// "ovqat — tushlik", "Transport: taksi", "+998901234567 onamga" or just a free comment.
    static func applyReply(_ text: String, to tx: FinTransaction, ctx: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cats = FinanceEngine.categories(ctx).filter { $0.kind == tx.kind }
        var matched: FinCategory? = nil
        var note = trimmed

        for sep in [":", "—", " - ", ","] {
            guard let r = trimmed.range(of: sep) else { continue }
            let head = trimmed[..<r.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
            guard head.count >= 3 else { continue }
            if let c = cats.first(where: { $0.name.lowercased() == head })
                ?? cats.first(where: { $0.name.lowercased().contains(head) }) {
                matched = c
                note = String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        if matched == nil {
            let lower = trimmed.lowercased()
            matched = cats.first { c in
                c.name.lowercased()
                    .components(separatedBy: CharacterSet.letters.inverted)
                    .contains { w in w.count >= 4 && lower.contains(w) }
            }
        }

        if matched == nil {
            let guess = FinanceEngine.guessCategory(text: trimmed, kind: tx.kind, ctx: ctx)
            if guess != "Boshqa xarajat" && guess != "Boshqa kirim" {
                matched = cats.first { $0.name == guess }
            }
        }

        tx.note = note.isEmpty ? trimmed : note
        if let matched { setCategory(matched.name, for: tx, ctx: ctx) }
        tx.needsReview = false
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText
        let idString = info["txID"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let idString, let id = UUID(uuidString: idString) {
                    ReviewHandler.handle(txID: id, action: action, text: text)
                }
            }
            completionHandler()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        Notifier.registerReviewCategories()
        return true
    }
}

@MainActor
final class OverlayWindow {
    static let shared = OverlayWindow()
    private var window: UIWindow?
    private var hideTask: Task<Void, Never>?

    func setVisible(_ visible: Bool) {
        hideTask?.cancel()
        if visible {
            ensureWindow()
            window?.isUserInteractionEnabled = true
            window?.isHidden = false
        } else {
            // Stop catching touches right away; hide after the fade-out finishes.
            window?.isUserInteractionEnabled = false
            restoreMainWindow()
            hideTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled else { return }
                self.window?.isHidden = true
                self.restoreMainWindow()
            }
        }
    }

    private func restoreMainWindow() {
        guard let scene = window?.windowScene else { return }
        if let main = scene.windows.first(where: { $0 !== window && !$0.isHidden }), !main.isKeyWindow {
            main.makeKey()
        }
    }

    private func ensureWindow() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState != .unattached }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        let host = UIHostingController(rootView: SecureOverlayView()
            .environment(AppLock.shared)
            .environment(OverlayState.shared))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        window = w
    }
}

struct SecureOverlayView: View {
    @Environment(AppLock.self) private var lock
    @Environment(OverlayState.self) private var state
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("pinSet") private var pinSet = false
    @AppStorage("appearance") private var appearance = "dark"

    private var scheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "system": return nil
        default: return .dark
        }
    }

    var body: some View {
        ZStack {
            if onboarded && pinSet && lock.isLocked && !state.showSplash {
                LockScreen()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
            if state.privacy && !state.showSplash {
                PrivacyCover().transition(.opacity)
            }
            if state.showSplash {
                SplashView().transition(.opacity.combined(with: .scale(scale: 1.08)))
            }
        }
        .animation(.smooth(duration: 0.4), value: lock.isLocked)
        .animation(.smooth(duration: 0.3), value: state.privacy)
        .animation(.smooth(duration: 0.5), value: state.showSplash)
        .preferredColorScheme(scheme)
        .tint(Palette.accent)
    }
}
