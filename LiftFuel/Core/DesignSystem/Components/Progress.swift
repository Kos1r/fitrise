import SwiftUI

/// Circular progress ring with a gradient stroke. Over-target values wrap with a darker second lap.
struct ProgressRing: View {
    var progress: Double
    var tint: Color = .brand
    var lineWidth: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.7), tint], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .overlay(
                        Circle()
                            .trim(from: 0, to: min(progress - 1, 1))
                            .stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(reduceMotion ? nil : .gentleSpring, value: progress)
        .accessibilityHidden(true)
    }
}

/// Labelled horizontal macro bar: "Protein 112 / 150 g · 38 g left".
struct MacroBar: View {
    var title: LocalizedStringKey
    var eaten: Double
    var target: Double
    var unit: String = "g"
    var tint: Color

    private var progress: Double { target > 0 ? eaten / target : 0 }
    private var remaining: Double { target - eaten }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs + 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(eaten.rounded())) / \(Int(target.rounded())) \(unit)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.15))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(8, proxy.size.width * min(progress, 1)))
                        .opacity(eaten > 0 ? 1 : 0)
                }
            }
            .frame(height: 10)
            Text(remaining >= 0
                 ? String(localized: "\(Int(remaining.rounded())) \(unit) left")
                 : String(localized: "\(Int((-remaining).rounded())) \(unit) over"))
                .font(.caption)
                .foregroundStyle(remaining >= 0 ? Color.secondary : tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(Int(eaten.rounded())) of \(Int(target.rounded())) \(unit), \(Int(abs(remaining).rounded())) \(unit) \(remaining >= 0 ? String(localized: "left") : String(localized: "over"))"))
    }
}

/// Calorie ring with the remaining number in the middle.
struct CalorieRing: View {
    var eaten: Double
    var target: Double
    var size: CGFloat = 150

    private var remaining: Double { target - eaten }

    var body: some View {
        ZStack {
            ProgressRing(progress: target > 0 ? eaten / target : 0, tint: .brand, lineWidth: size * 0.09)
            VStack(spacing: 0) {
                Text("\(Int(abs(remaining).rounded()))")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(remaining >= 0 ? LocalizedStringKey("kcal left") : LocalizedStringKey("kcal over"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories")
        .accessibilityValue(Text("\(Int(eaten.rounded())) of \(Int(target.rounded())) kilocalories eaten"))
    }
}
