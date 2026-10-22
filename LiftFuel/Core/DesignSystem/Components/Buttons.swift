import SwiftUI

/// Big, thumb-friendly primary action.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .brand
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(Color.black.opacity(0.88))
            .padding(.vertical, compact ? Spacing.s + 2 : Spacing.l)
            .padding(.horizontal, compact ? Spacing.l : Spacing.xl)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 40 : 56)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(tint.gradient)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappySpring, value: configuration.isPressed)
    }
}

/// Secondary action on a tinted translucent background.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .brand
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(tint)
            .padding(.vertical, compact ? Spacing.s + 2 : Spacing.m + 2)
            .padding(.horizontal, compact ? Spacing.m : Spacing.l)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 40 : 50)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappySpring, value: configuration.isPressed)
    }
}

/// Round icon button (e.g. steppers, toolbar-ish actions inside cards).
struct CircleIconButton: View {
    var symbol: String
    var tint: Color = .brand
    var size: CGFloat = 44
    var accessibilityLabel: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(tint.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Capsule chip for filters and tags.
struct Chip: View {
    var title: String
    var symbol: String?
    var tint: Color = .brand
    var isSelected = true

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.s + 2)
        .padding(.vertical, Spacing.xs + 1)
        .foregroundStyle(isSelected ? tint : Color.secondary)
        .background(
            Capsule().fill(isSelected ? tint.opacity(0.16) : Color.cardElevated)
        )
    }
}

/// Selectable card row used in onboarding/settings pickers.
struct SelectableRow: View {
    var title: String
    var detail: String?
    var symbol: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color.brand : .secondary)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    if let detail {
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.brand : Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .padding(Spacing.l)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(isSelected ? Color.brand : Color.hairline, lineWidth: isSelected ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
