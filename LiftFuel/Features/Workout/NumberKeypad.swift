import SwiftUI

/// Which cell of which set the keypad is editing.
enum SetField: Hashable {
    case weight(UUID)
    case reps(UUID)

    var setID: UUID {
        switch self {
        case .weight(let id), .reps(let id): id
        }
    }

    var isWeight: Bool {
        if case .weight = self { return true }
        return false
    }
}

/// Text-buffer logic for the custom keypad, independent of the UI (unit-testable).
struct KeypadBuffer: Equatable {
    var text: String
    var allowsDecimal: Bool
    /// The first key press replaces the existing value (like a fresh entry).
    var isFresh = true

    init(value: Double, allowsDecimal: Bool) {
        self.allowsDecimal = allowsDecimal
        self.text = allowsDecimal ? Self.plain(value) : String(Int(value))
    }

    /// Locale-independent text ("42.5", never "42,5") so `Double(text)` always parses.
    static func plain(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    var value: Double { Double(text) ?? 0 }

    mutating func press(_ key: String) {
        if isFresh {
            text = ""
            isFresh = false
        }
        if key == "." {
            guard allowsDecimal, !text.contains(".") else { return }
            text = text.isEmpty ? "0." : text + "."
            return
        }
        // Max 2 decimals, max 4 integer digits.
        if let dot = text.firstIndex(of: ".") {
            guard text.distance(from: dot, to: text.endIndex) <= 2 else { return }
        } else if text.count >= 4 {
            return
        }
        text = text == "0" ? key : text + key
    }

    mutating func backspace() {
        isFresh = false
        if !text.isEmpty { text.removeLast() }
    }

    mutating func step(by delta: Double) {
        let next = max(0, value + delta)
        text = allowsDecimal ? Self.plain(next) : String(Int(next))
        isFresh = true
    }
}

/// Compact numeric keypad with ± steppers, shown at the bottom of the workout screen.
struct NumberKeypad: View {
    var title: LocalizedStringKey
    var unit: String
    @Binding var buffer: KeypadBuffer
    var step: Double
    var onNext: () -> Void
    var onDone: () -> Void

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]

    var body: some View {
        VStack(spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(buffer.text.isEmpty ? "0" : buffer.text)
                    .font(.statLarge)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: Spacing.s) {
                stepperButton(delta: -step)
                stepperButton(delta: step)
            }

            HStack(alignment: .top, spacing: Spacing.s) {
                VStack(spacing: Spacing.s) {
                    ForEach(0..<4, id: \.self) { row in
                        HStack(spacing: Spacing.s) {
                            ForEach(keys[(row * 3)..<(row * 3 + 3)], id: \.self) { key in
                                keyButton(key)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: Spacing.s) {
                    Button(action: onNext) {
                        Text("Next")
                            .font(.headline)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(KeyStyle(tint: .brand.opacity(0.18), foreground: .brand))
                    .accessibilityIdentifier("keypad.next")
                    Button(action: onDone) {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(KeyStyle(tint: .brand, foreground: Color.onAccent))
                    .accessibilityIdentifier("keypad.done")
                }
                .frame(width: 84)
            }
            .frame(height: 4 * 48 + 3 * Spacing.s)
        }
        .padding(Spacing.l)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.horizontal, Spacing.s)
    }

    private func stepperButton(delta: Double) -> some View {
        Button {
            buffer.step(by: delta)
            Haptics.selection()
        } label: {
            Text("\(delta > 0 ? "+" : "−")\(StrengthMath.formatWeight(abs(delta)))")
                .font(.headline.monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(KeyStyle(tint: Color.cardElevated, foreground: .primary))
        .accessibilityLabel(delta > 0 ? Text("Increase by \(StrengthMath.formatWeight(abs(delta)))") : Text("Decrease by \(StrengthMath.formatWeight(abs(delta)))"))
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        let disabled = key == "." && !buffer.allowsDecimal
        Button {
            if key == "⌫" {
                buffer.backspace()
            } else {
                buffer.press(key)
            }
            Haptics.selection()
        } label: {
            Group {
                if key == "⌫" {
                    Image(systemName: "delete.left")
                } else {
                    Text(key)
                }
            }
            .font(.title2.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: .infinity)
        }
        .buttonStyle(KeyStyle(tint: Color.cardBackground, foreground: .primary))
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .accessibilityLabel(key == "⌫" ? Text("Delete") : Text(key))
        .accessibilityIdentifier("keypad.\(key)")
    }
}

private struct KeyStyle: ButtonStyle {
    var tint: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(tint, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
