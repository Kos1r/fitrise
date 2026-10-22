import SwiftUI

/// Base card surface used across the app.
struct Card<Content: View>: View {
    var padding: CGFloat = Spacing.l
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.hairline.opacity(0.6), lineWidth: 0.5)
            )
    }
}

/// Card header with an SF Symbol, title and optional trailing accessory.
struct CardHeader<Trailing: View>: View {
    var title: LocalizedStringKey
    var symbol: String
    var tint: Color = .brand
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.cardTitle)
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, symbol: String, tint: Color = .brand) {
        self.init(title: title, symbol: symbol, tint: tint) { EmptyView() }
    }
}

/// Small uppercase label above a group of content.
struct SectionLabel: View {
    var text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.sectionLabel)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A big number with a caption — used in stat rows.
struct StatTile: View {
    var value: String
    var label: LocalizedStringKey
    var symbol: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
                Text(value)
                    .font(.statSmall)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Friendly empty state with an icon, message and optional action.
struct EmptyStateView: View {
    var symbol: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.brand)
                .padding(Spacing.l)
                .background(Color.brand.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Shimmering placeholder block for loading states.
struct SkeletonBlock: View {
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 8
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.cardElevated)
            .frame(height: height)
            .opacity(phase ? 0.45 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    phase = true
                }
            }
            .accessibilityHidden(true)
    }
}
