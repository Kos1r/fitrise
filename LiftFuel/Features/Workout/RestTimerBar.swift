import SwiftUI

/// Floating rest-timer pill with ±15 s and skip.
struct RestTimerBar: View {
    @Environment(RestTimerManager.self) private var restTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            HStack(spacing: Spacing.m) {
                ZStack {
                    ProgressRing(progress: restTimer.progress(at: context.date), tint: .brand, lineWidth: 5)
                    Image(systemName: "timer")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.brand)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 0) {
                    Text(Format.duration(restTimer.remaining(at: context.date).rounded(.up)))
                        .font(.statMedium)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text("Rest · next \(restTimer.nextSetDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                timerButton("−15", label: "Remove 15 seconds") { restTimer.adjust(by: -15) }
                timerButton("+15", label: "Add 15 seconds") { restTimer.adjust(by: 15) }
                Button {
                    restTimer.skip()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(Color.brand, in: Circle())
                        .foregroundStyle(Color.onAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip rest")
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(.horizontal, Spacing.s)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest timer")
    }

    private func timerButton(_ title: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 44, height: 40)
                .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
