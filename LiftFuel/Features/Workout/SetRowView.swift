import SwiftUI

/// One set: number/type · previous · kg · reps · ✓
struct SetRowView: View {
    let set: SetEntry
    var displayNumber: Int
    var previous: SetEntry?
    var focusedField: SetField?
    var onFocus: (SetField) -> Void
    var onToggleComplete: () -> Void
    var onChangeType: (SetType) -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            typeMenu
                .frame(width: 34)
            previousText
                .frame(maxWidth: .infinity)
            valueCell(text: StrengthMath.formatWeight(set.weight), field: .weight(set.id), label: "kg")
            valueCell(text: "\(set.reps)", field: .reps(set.id), label: "reps")
            completeButton
        }
        .padding(.vertical, Spacing.xs)
        .background(set.isCompleted ? Color.brand.opacity(0.10) : Color.clear)
        .animation(.snappySpring, value: set.isCompleted)
    }

    private var typeMenu: some View {
        Menu {
            Picker("Set type", selection: Binding(get: { set.setType }, set: onChangeType)) {
                ForEach(SetType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            Divider()
            Button("Delete set", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            ZStack {
                Circle()
                    .fill(set.setType == .normal ? Color.cardElevated : set.setType.color.opacity(0.2))
                Text(set.setType.badge ?? "\(displayNumber)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(set.setType == .normal ? Color.primary : set.setType.color)
            }
            .frame(width: 30, height: 30)
            .overlay(alignment: .topTrailing) {
                if set.isPR {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color("ShouldersColor"))
                        .offset(x: 6, y: -4)
                }
            }
        }
        .accessibilityLabel(Text("Set \(displayNumber), \(set.setType.title)\(set.isPR ? ", personal record" : "")"))
        .accessibilityHint("Change set type or delete")
    }

    private var previousText: some View {
        Group {
            if let previous {
                Text("\(StrengthMath.formatWeight(previous.weight)) × \(previous.reps)")
            } else {
                Text("—")
            }
        }
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityLabel(previous.map { Text("Last time \(StrengthMath.formatWeight($0.weight)) kilograms times \($0.reps)") } ?? Text("No previous set"))
    }

    private func valueCell(text: String, field: SetField, label: String) -> some View {
        let isFocused = focusedField == field
        return Button {
            onFocus(field)
        } label: {
            Text(text)
                .font(.numeric)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 66, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(isFocused ? Color.brand.opacity(0.22) : Color.cardElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .strokeBorder(isFocused ? Color.brand : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(label == "kg" ? String(localized: "Weight") : String(localized: "Reps")): \(text) \(label)"))
        .accessibilityIdentifier(field.isWeight ? "set.weight" : "set.reps")
    }

    private var completeButton: some View {
        Button(action: onToggleComplete) {
            Image(systemName: "checkmark")
                .font(.body.weight(.heavy))
                .foregroundStyle(set.isCompleted ? Color.black.opacity(0.85) : Color.secondary)
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(set.isCompleted ? Color.brand : Color.cardElevated)
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: set.isCompleted)
        .accessibilityLabel(set.isCompleted ? "Mark set as not done" : "Complete set")
        .accessibilityIdentifier("set.complete")
    }
}

/// Column labels above the set rows.
struct SetColumnsHeader: View {
    var body: some View {
        HStack(spacing: Spacing.s) {
            Text("Set").frame(width: 34)
            Text("Previous").frame(maxWidth: .infinity)
            Text("kg").frame(width: 66)
            Text("Reps").frame(width: 66)
            Image(systemName: "checkmark").frame(width: 44)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .accessibilityHidden(true)
    }
}
