import SwiftUI
import UIKit

/// Colored capsule with the split icon and name.
struct SplitBadge: View {
    var split: SplitDay
    var compact = false

    var body: some View {
        Label {
            Text(split.title)
        } icon: {
            Image(systemName: split.symbol)
        }
        .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, compact ? Spacing.s : Spacing.m)
        .padding(.vertical, compact ? Spacing.xxs + 1 : Spacing.xs + 1)
        .foregroundStyle(split.color)
        .background(split.color.opacity(0.16), in: Capsule())
    }
}

/// Muscle-group chip with its accent color.
struct MuscleChip: View {
    var group: MuscleGroup

    var body: some View {
        Chip(title: group.title, symbol: group.symbol, tint: group.color)
    }
}

/// Vertical accent bar + icon used at the leading edge of exercise rows.
struct MuscleAccent: View {
    var group: MuscleGroup
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: group.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(group.color)
            .frame(width: size, height: size)
            .background(group.color.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Small trophy badge for personal records.
struct PRBadge: View {
    var body: some View {
        Label("PR", systemImage: "trophy.fill")
            .font(.caption2.weight(.heavy))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.black.opacity(0.85))
            .background(Color("ShouldersColor").gradient, in: Capsule())
            .accessibilityLabel("Personal record")
    }
}

@MainActor
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
