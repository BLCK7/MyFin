import SwiftUI

enum Money {
    static func symbol(_ code: String) -> String {
        switch code {
        case "UZS": return "so'm"
        case "USD": return "$"
        case "EUR": return "€"
        case "RUB": return "₽"
        default: return code
        }
    }

    static func decimals(_ code: String) -> Int { code == "UZS" ? 0 : 2 }

    static func number(_ value: Double, decimals: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.decimalSeparator = ","
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = decimals
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "0"
    }

    static func format(_ value: Double, _ code: String, signed: Bool = false) -> String {
        let num = number(abs(value), decimals: decimals(code))
        var sign = value < 0 ? "−" : ""
        if signed && value > 0 { sign = "+" }
        switch code {
        case "USD", "EUR": return "\(sign)\(symbol(code))\(num)"
        default: return "\(sign)\(num) \(symbol(code))"
        }
    }

    static func compact(_ value: Double) -> String {
        let a = abs(value)
        let sign = value < 0 ? "−" : ""
        if a >= 1_000_000_000 { return sign + number(a / 1_000_000_000, decimals: 1) + " mlrd" }
        if a >= 1_000_000 { return sign + number(a / 1_000_000, decimals: 1) + " mln" }
        if a >= 1_000 { return sign + number(a / 1_000, decimals: 0) + " ming" }
        return sign + number(a, decimals: 0)
    }
}

struct AmountText: View {
    let value: Double
    var currency: String = "UZS"
    var font: Font = .body
    var signed: Bool = false
    var color: Color? = nil
    @AppStorage("hideAmounts") private var hide = false

    var body: some View {
        Text(hide ? "••••••" : Money.format(value, currency, signed: signed))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color ?? Color.primary)
            .contentTransition(.numericText(value: value))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

struct IconBadge: View {
    let icon: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: size * 0.32)
            )
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 4)
    }
}

struct ProgressCapsule: View {
    let progress: Double
    var color: Color = Palette.accent
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: height)
    }
}

struct RingProgress: View {
    let progress: Double
    var color: Color = Palette.accent
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct StatPill: View {
    let title: String
    let value: Double
    let currency: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            AmountText(value: value, currency: currency, font: .subheadline.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ColorSwatchPicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
            ForEach(Palette.swatches, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(height: 34)
                    .overlay {
                        if hex == selection {
                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                        }
                    }
                    .onTapGesture { selection = hex }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AmountField: View {
    let title: String
    @Binding var text: String
    var currency: String = "UZS"

    var body: some View {
        HStack {
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(Money.symbol(currency))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

extension Date {
    var uzShort: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "uz_Latn_UZ")
        f.dateFormat = "d MMM, HH:mm"
        return f.string(from: self)
    }

    var uzDay: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Bugun" }
        if cal.isDateInYesterday(self) { return "Kecha" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "uz_Latn_UZ")
        f.dateFormat = "d MMMM, EEEE"
        return f.string(from: self)
    }

    var uzMonthYear: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "uz_Latn_UZ")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: self).capitalized
    }

    var uzDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "uz_Latn_UZ")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: self)
    }
}

func parseAmount(_ text: String) -> Double? {
    SMSParser.parseNumber(text)
}
