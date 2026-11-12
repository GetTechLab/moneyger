import SwiftUI

/// Shared colors and gradients for the app's visual style.
enum AppTheme {
    static let accent = Color(red: 0.38, green: 0.31, blue: 0.96)
    static let expense = Color(red: 0.94, green: 0.33, blue: 0.40)
    static let income = Color(red: 0.13, green: 0.75, blue: 0.53)

    /// Main brand gradient used on the dashboard hero card.
    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.36, green: 0.24, blue: 0.94),
            Color(red: 0.60, green: 0.27, blue: 0.93),
            Color(red: 0.93, green: 0.36, blue: 0.62)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Gradient pairs for account cards; picked by bank name so each bank keeps the same color.
    static let cardGradients: [[Color]] = [
        [Color(red: 0.36, green: 0.24, blue: 0.94), Color(red: 0.62, green: 0.30, blue: 0.95)],
        [Color(red: 0.05, green: 0.55, blue: 0.85), Color(red: 0.20, green: 0.80, blue: 0.85)],
        [Color(red: 0.95, green: 0.40, blue: 0.35), Color(red: 0.98, green: 0.65, blue: 0.30)],
        [Color(red: 0.10, green: 0.62, blue: 0.48), Color(red: 0.35, green: 0.82, blue: 0.55)],
        [Color(red: 0.85, green: 0.25, blue: 0.55), Color(red: 0.95, green: 0.45, blue: 0.70)],
        [Color(red: 0.15, green: 0.17, blue: 0.28), Color(red: 0.32, green: 0.36, blue: 0.50)]
    ]

    static func cardGradient(for key: String) -> LinearGradient {
        // Deterministic hash: String.hashValue changes every launch
        let index = key.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % cardGradients.count
        return LinearGradient(colors: cardGradients[index], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func amountColor(isExpense: Bool) -> Color {
        isExpense ? expense : income
    }

    /// Categorical chart palette, validated for color-vision deficiency in adjacent order
    /// (stacked bars). Each slot has its own light/dark step. Assign in order, never cycle.
    static let seriesColors: [Color] = [
        Color(light: 0x2A78D6, dark: 0x3987E5), // blue
        Color(light: 0xEB6834, dark: 0xD95926), // orange
        Color(light: 0x1BAF7A, dark: 0x199E70), // aqua
        Color(light: 0xEDA100, dark: 0xC98500), // yellow
        Color(light: 0xE87BA4, dark: 0xD55181), // magenta
        Color(light: 0x008300, dark: 0x008300), // green
        Color(light: 0x4A3AA7, dark: 0x9085E9), // violet
        Color(light: 0xE34948, dark: 0xE66767)  // red
    ]

    /// Stable color per currency code, drawn from the card palette.
    static func currencyColor(for code: String) -> Color {
        let index = code.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % cardGradients.count
        return cardGradients[index][0]
    }

    /// Flag emoji for a currency code (e.g. "USD" → 🇺🇸), nil for non-country currencies.
    static func currencyFlag(for code: String) -> String? {
        let regionCode = code == "EUR" ? "EU" : String(code.prefix(2))
        guard regionCode == "EU" || Locale.Region.isoRegions.contains(Locale.Region(regionCode)) else {
            return nil
        }
        // Regional indicator symbols start at U+1F1E6 for "A"
        let scalars = regionCode.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }
        return String(String.UnicodeScalarView(scalars))
    }
}

/// Circular badge with the currency's flag, or its symbol when there's no flag.
struct CurrencyBadge: View {
    let code: String
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(AppTheme.currencyColor(for: code).opacity(0.15))
            if let flag = AppTheme.currencyFlag(for: code) {
                Text(flag).font(.system(size: size * 0.55))
            } else {
                Text(code.prefix(1))
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.currencyColor(for: code))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension Color {
    /// Color with separate hex values for light and dark appearance.
    init(light: UInt32, dark: UInt32) {
        func components(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
        }
        self.init(uiColor: UIColor { traits in
            let (r, g, b) = components(traits.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }
}

extension TransactionCategory {
    var color: Color {
        switch self {
        case .food: return Color(red: 1.00, green: 0.58, blue: 0.20)
        case .transport: return Color(red: 0.20, green: 0.55, blue: 0.98)
        case .health: return Color(red: 0.96, green: 0.30, blue: 0.42)
        case .shopping: return Color(red: 0.69, green: 0.35, blue: 0.95)
        case .entertainment: return Color(red: 0.36, green: 0.36, blue: 0.92)
        case .bills: return Color(red: 0.98, green: 0.76, blue: 0.18)
        case .investment: return Color(red: 0.10, green: 0.72, blue: 0.75)
        case .income: return AppTheme.income
        case .transfer: return Color(red: 0.40, green: 0.62, blue: 0.80)
        case .other: return Color(red: 0.58, green: 0.60, blue: 0.66)
        }
    }
}

/// Rounded square icon tile tinted with a category color.
struct CategoryIcon: View {
    let category: TransactionCategory
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: category.icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [category.color, category.color.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Standard elevated card container used across screens.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }

    /// Clear Liquid Glass on iOS 26+, translucent white fill on earlier versions.
    /// Intended for controls placed on top of the colorful hero gradient.
    @ViewBuilder
    func heroGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .clear.interactive() : .clear, in: shape)
        } else {
            background(.white.opacity(0.2), in: shape)
        }
    }

    /// Spins a symbol while `isActive` is true; no-op before iOS 18.
    @ViewBuilder
    func rotatingSymbol(isActive: Bool) -> some View {
        if #available(iOS 18.0, *) {
            symbolEffect(.rotate, isActive: isActive)
        } else {
            self
        }
    }
}
