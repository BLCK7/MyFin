import SwiftUI

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakes), y: 0))
    }
}

struct BrandTitle: View {
    var size: CGFloat = 40

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("SAMINOV")
                .font(.system(size: size, weight: .black, design: .rounded))
                .tracking(size * 0.06)
                .foregroundStyle(LinearGradient(colors: [.white, Color(hex: "#C7D2FE"), Palette.accent],
                                                startPoint: .top, endPoint: .bottom))
            Text("’s financer")
                .font(.system(size: size * 0.58, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

struct PinDots: View {
    let count: Int
    let filled: Int
    var error = false

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i < filled ? (error ? Palette.expense : Color.primary) : Color.primary.opacity(0.18))
                    .frame(width: 14, height: 14)
                    .scaleEffect(i < filled ? 1.15 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: filled)
            }
        }
    }
}

struct PinKeypad: View {
    var biometricIcon: String? = nil
    var disabled = false
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    var onBiometric: (() -> Void)? = nil

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            VStack(spacing: 16) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 26) {
                        ForEach(row, id: \.self) { d in key(d) }
                    }
                }
                HStack(spacing: 26) {
                    if let biometricIcon, let onBiometric {
                        Button(action: onBiometric) {
                            Image(systemName: biometricIcon)
                                .font(.system(size: 28, weight: .medium))
                                .frame(width: 76, height: 76)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 76, height: 76)
                    }
                    key("0")
                    Button {
                        Haptics.tap()
                        onDelete()
                    } label: {
                        Image(systemName: "delete.left.fill")
                            .font(.system(size: 24, weight: .medium))
                            .frame(width: 76, height: 76)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private func key(_ d: String) -> some View {
        Button {
            Haptics.tap()
            onDigit(d)
        } label: {
            Text(d)
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .frame(width: 76, height: 76)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

struct LockScreen: View {
    @Environment(AppLock.self) private var lock
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @State private var entered = ""
    @State private var shakes: CGFloat = 0
    @State private var error = false
    @State private var message = ""
    @State private var lockedUntil: Date? = PasscodeStore.lockoutUntil
    @State private var biometricRunning = false
    var autoBiometric = true

    private let length = PasscodeStore.length

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 22) {
                Spacer(minLength: 30)
                BrandTitle(size: 30)
                Image(systemName: lockedUntil == nil ? "lock.fill" : "lock.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 70, height: 70)
                    .glassEffect(.regular, in: .circle)
                    .symbolEffect(.bounce, value: shakes)
                Text("PIN-kodni kiriting")
                    .font(.headline)
                PinDots(count: length, filled: entered.count, error: error)
                    .modifier(ShakeEffect(animatableData: shakes))
                statusText
                    .frame(height: 20)
                Spacer(minLength: 10)
                PinKeypad(biometricIcon: faceIDEnabled && Biometrics.available ? Biometrics.icon : nil,
                          disabled: lockedUntil != nil,
                          onDigit: append, onDelete: deleteLast,
                          onBiometric: { Task { await biometric() } })
                    .padding(.bottom, 36)
            }
            .padding(.horizontal, 24)
        }
        .task {
            guard autoBiometric, faceIDEnabled, lockedUntil == nil else { return }
            try? await Task.sleep(for: .milliseconds(300))
            await biometric()
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if let until = lockedUntil {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = max(0, Int(until.timeIntervalSince(ctx.date).rounded(.up)))
                Text(left > 0 ? "Juda ko'p urinish. \(left) soniyadan keyin qayta urining." : "Qayta urinishingiz mumkin")
                    .font(.footnote)
                    .foregroundStyle(Palette.expense)
                    .onChange(of: left) { _, v in if v == 0 { lockedUntil = nil } }
            }
        } else {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.expense)
        }
    }

    private func append(_ d: String) {
        guard entered.count < length, lockedUntil == nil else { return }
        error = false
        message = ""
        entered.append(d)
        if entered.count == length { check() }
    }

    private func deleteLast() {
        guard !entered.isEmpty else { return }
        entered.removeLast()
        error = false
    }

    private func check() {
        switch PasscodeStore.verify(entered) {
        case .success:
            Haptics.success()
            withAnimation(.smooth(duration: 0.35)) { lock.unlock() }
        case .failure(let remaining):
            fail(remaining > 0 ? "Noto'g'ri PIN-kod. Yana \(remaining) ta urinish." : "Noto'g'ri PIN-kod.")
        case .lockedOut(let until):
            fail("")
            lockedUntil = until
        }
    }

    private func fail(_ text: String) {
        Haptics.error()
        error = true
        message = text
        withAnimation(.linear(duration: 0.4)) { shakes += 1 }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            entered = ""
            error = false
        }
    }

    private func biometric() async {
        guard !biometricRunning else { return }
        biometricRunning = true
        defer { biometricRunning = false }
        if await Biometrics.authenticateBiometric(reason: "MyFin'ni ochish") {
            PasscodeStore.resetFailures()
            Haptics.success()
            withAnimation(.smooth(duration: 0.35)) { lock.unlock() }
        }
    }
}

struct PasscodeSetupView: View {
    enum Mode { case create, change }

    let mode: Mode
    let onComplete: () -> Void
    var onCancel: (() -> Void)? = nil

    private enum Stage { case current, new, confirm }

    @State private var stage: Stage = .new
    @State private var length = 6
    @State private var entered = ""
    @State private var first = ""
    @State private var shakes: CGFloat = 0
    @State private var error = false
    @State private var message = ""

    private var title: String {
        switch stage {
        case .current: return "Joriy PIN-kodni kiriting"
        case .new: return "Yangi PIN-kod o'ylab toping"
        case .confirm: return "PIN-kodni takrorlang"
        }
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 22) {
                HStack {
                    if let onCancel {
                        Button("Bekor", action: onCancel).buttonStyle(.glass)
                    }
                    Spacer()
                }
                .frame(height: 44)
                Spacer(minLength: 0)
                Image(systemName: stage == .confirm ? "checkmark.shield.fill" : "lock.shield.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 76, height: 76)
                    .glassEffect(.regular, in: .circle)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.title3.bold())
                    .contentTransition(.opacity)
                PinDots(count: currentLength, filled: entered.count, error: error)
                    .modifier(ShakeEffect(animatableData: shakes))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(error ? Palette.expense : Color.secondary)
                    .frame(height: 20)
                if stage == .new {
                    Picker("Uzunlik", selection: $length) {
                        Text("4 raqam").tag(4)
                        Text("6 raqam").tag(6)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .onChange(of: length) { _, _ in entered = "" }
                }
                Spacer(minLength: 0)
                PinKeypad(onDigit: append, onDelete: { if !entered.isEmpty { entered.removeLast() } })
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            stage = (mode == .change && PasscodeStore.isSet) ? .current : .new
            length = PasscodeStore.isSet ? PasscodeStore.length : 6
        }
    }

    private var currentLength: Int {
        stage == .current ? PasscodeStore.length : length
    }

    private func append(_ d: String) {
        guard entered.count < currentLength else { return }
        error = false
        message = ""
        entered.append(d)
        guard entered.count == currentLength else { return }

        switch stage {
        case .current:
            switch PasscodeStore.verify(entered) {
            case .success:
                advance(to: .new)
            case .failure:
                fail("Noto'g'ri PIN-kod")
            case .lockedOut:
                fail("Juda ko'p urinish, keyinroq qayta urining")
            }
        case .new:
            if Set(entered).count == 1 || "0123456789".contains(entered) || "9876543210".contains(entered) {
                fail("Juda oddiy PIN. Boshqasini tanlang.")
                return
            }
            first = entered
            advance(to: .confirm)
        case .confirm:
            if entered == first {
                PasscodeStore.set(entered)
                Haptics.success()
                onComplete()
            } else {
                first = ""
                fail("Mos kelmadi, qaytadan boshlang")
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    withAnimation(.smooth) { stage = .new }
                }
            }
        }
    }

    private func advance(to next: Stage) {
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.smooth) {
                stage = next
                entered = ""
            }
        }
    }

    private func fail(_ text: String) {
        Haptics.error()
        error = true
        message = text
        withAnimation(.linear(duration: 0.4)) { shakes += 1 }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            entered = ""
        }
    }
}

struct SplashView: View {
    @State private var ring: CGFloat = 0
    @State private var revealed = 0
    @State private var showTail = false
    @State private var glow = false
    @State private var iconScale: CGFloat = 0.6

    private let word = Array("SAMINOV")

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 30) {
                ZStack {
                    Circle()
                        .fill(Palette.accent.opacity(0.45))
                        .frame(width: 170, height: 170)
                        .blur(radius: 45)
                        .scaleEffect(glow ? 1.2 : 0.7)
                    Circle()
                        .trim(from: 0, to: ring)
                        .stroke(AngularGradient(colors: [Palette.income, Palette.accent, Color(hex: "#C084FC"),
                                                         Palette.expense, Palette.warning, Palette.income],
                                                center: .center),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 92, height: 92)
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .scaleEffect(iconScale)
                }
                .frame(width: 150, height: 150)
                .glassEffect(.regular, in: .circle)

                VStack(spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        HStack(spacing: 2) {
                            ForEach(0..<word.count, id: \.self) { i in
                                Text(String(word[i]))
                                    .font(.system(size: 42, weight: .black, design: .rounded))
                                    .opacity(i < revealed ? 1 : 0)
                                    .offset(y: i < revealed ? 0 : 16)
                                    .blur(radius: i < revealed ? 0 : 8)
                            }
                        }
                        .foregroundStyle(LinearGradient(colors: [.white, Color(hex: "#C7D2FE"), Palette.accent],
                                                        startPoint: .top, endPoint: .bottom))
                        Text("’s financer")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .opacity(showTail ? 1 : 0)
                            .offset(x: showTail ? 0 : -10)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 20)

                    Text("Shaxsiy moliya boshqaruvi")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .opacity(showTail ? 0.8 : 0)
                }
            }
        }
        .task {
            withAnimation(.easeInOut(duration: 1.0)) { ring = 1 }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) { iconScale = 1 }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glow = true }
            for i in 1...word.count {
                try? await Task.sleep(for: .milliseconds(70))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { revealed = i }
            }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.smooth(duration: 0.4)) { showTail = true }
        }
    }
}

struct AppearAnimation: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 22)
            .scaleEffect(shown ? 1 : 0.97)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(Double(index) * 0.06)) {
                    shown = true
                }
            }
    }
}

extension View {
    func appearAnimation(_ index: Int) -> some View { modifier(AppearAnimation(index: index)) }
}
