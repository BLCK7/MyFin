import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

enum Palette {
    static let accent = Color(hex: "#7C8CFF")
    static let income = Color(hex: "#34D399")
    static let expense = Color(hex: "#FB7185")
    static let transfer = Color(hex: "#60A5FA")
    static let warning = Color(hex: "#FBBF24")
    static let swatches = ["#4F7CFF", "#7C3AED", "#EC4899", "#F59E0B", "#10B981",
                           "#06B6D4", "#EF4444", "#64748B", "#0EA5E9", "#84CC16"]
}

struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme
    @State private var phase = false

    private var points: [SIMD2<Float>] {
        let mid: Float = phase ? 0.62 : 0.38
        return [
            SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 0.5), SIMD2<Float>(mid, 0.5), SIMD2<Float>(1, 0.5),
            SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1)
        ]
    }

    private var colors: [Color] {
        if scheme == .dark {
            return ["#0B1026", "#1B1446", "#0E2A47",
                    "#1A1F5C", "#2E1A63", "#0F3B4F",
                    "#090D1F", "#151033", "#0A2235"].map { Color(hex: $0) }
        }
        return ["#E8ECFF", "#F1E8FF", "#E3F4FF",
                "#DDE4FF", "#EBDDFF", "#D8F1F7",
                "#F4F6FF", "#EEE9FF", "#E6F6FB"].map { Color(hex: $0) }
    }

    var body: some View {
        MeshGradient(width: 3, height: 3, points: points, colors: colors)
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                    phase = true
                }
            }
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
