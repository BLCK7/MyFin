import SwiftUI

struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    private static let points: [SIMD2<Float>] = [
        SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
        SIMD2<Float>(0, 0.5), SIMD2<Float>(0.45, 0.5), SIMD2<Float>(1, 0.5),
        SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1)
    ]

    private static let dark: [Color] = ["#0B1026", "#1B1446", "#0E2A47",
                                        "#1A1F5C", "#2E1A63", "#0F3B4F",
                                        "#090D1F", "#151033", "#0A2235"].map { Color(hex: $0) }

    private static let light: [Color] = ["#E8ECFF", "#F1E8FF", "#E3F4FF",
                                         "#DDE4FF", "#EBDDFF", "#D8F1F7",
                                         "#F4F6FF", "#EEE9FF", "#E6F6FB"].map { Color(hex: $0) }

    var body: some View {
        MeshGradient(width: 3, height: 3, points: Self.points, colors: scheme == .dark ? Self.dark : Self.light)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = 26
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: .rect(cornerRadius: radius))
    }

    private var glass: Glass {
        if let tint { return .regular.tint(tint.opacity(0.22)) }
        return .regular
    }
}

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(AppBackground())
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}
