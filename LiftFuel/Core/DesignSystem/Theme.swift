import SwiftUI

// MARK: - Colors (asset catalog: Shared/SharedAssets.xcassets)

// Declared on `ShapeStyle where Self == Color` so they work both as `Color.x` and as `.x`
// in `foregroundStyle`, `fill`, `background`, etc.
extension ShapeStyle where Self == Color {
    /// The single strong accent (electric lime).
    static var brand: Color { Color("AccentColor") }
    static var appBackground: Color { Color("AppBackground") }
    static var cardBackground: Color { Color("CardBackground") }
    static var cardElevated: Color { Color("CardElevated") }
    static var hairline: Color { Color("Hairline") }
    static var protein: Color { Color("ProteinColor") }
    static var carbs: Color { Color("CarbsColor") }
    static var fat: Color { Color("FatColor") }
    static var water: Color { Color("WaterColor") }
}

// MARK: - Spacing & radii

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let card: CGFloat = 22
    static let button: CGFloat = 18
}

// MARK: - Typography (SF Pro, rounded numerals for stats; all scale with Dynamic Type)

extension Font {
    static let statHero = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let statLarge = Font.system(.title, design: .rounded, weight: .bold)
    static let statMedium = Font.system(.title3, design: .rounded, weight: .semibold)
    static let statSmall = Font.system(.headline, design: .rounded, weight: .semibold)
    static let cardTitle = Font.system(.headline, design: .default, weight: .semibold)
    static let sectionLabel = Font.system(.caption, design: .default, weight: .semibold)
    static let numeric = Font.system(.body, design: .rounded, weight: .semibold).monospacedDigit()
}

// MARK: - Animation

extension Animation {
    static let snappySpring = Animation.spring(response: 0.35, dampingFraction: 0.82)
    static let gentleSpring = Animation.spring(response: 0.5, dampingFraction: 0.85)
}

/// Respect Reduce Motion everywhere we animate.
struct MotionAware {
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Formatting helpers

enum Format {
    static func kcal(_ value: Double) -> String {
        "\(Int(value.rounded()).formatted()) kcal"
    }

    static func grams(_ value: Double) -> String {
        "\(Int(value.rounded())) g"
    }

    static func kg(_ value: Double) -> String {
        "\(StrengthMath.formatWeight(value)) kg"
    }

    static func ml(_ value: Double) -> String {
        if value >= 1000 {
            return "\((value / 1000).formatted(.number.precision(.fractionLength(0...1)))) L"
        }
        return "\(Int(value)) ml"
    }

    static func volume(_ value: Double) -> String {
        if value >= 10_000 {
            return "\((value / 1000).formatted(.number.precision(.fractionLength(1)))) t"
        }
        return "\(Int(value.rounded()).formatted()) kg"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes) min"
    }
}
