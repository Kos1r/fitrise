import ActivityKit
import SwiftUI
import WidgetKit

/// Rest timer on the Lock Screen and in the Dynamic Island.
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: "timer")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color("AccentColor"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest · \(context.attributes.exerciseName)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("Next: \(context.state.nextSetDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(timerInterval: Date.now...max(Date.now, context.state.endDate), countsDown: true)
                    .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.75))
            .activitySystemActionForegroundColor(Color("AccentColor"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "timer")
                        .font(.headline)
                        .foregroundStyle(Color("AccentColor"))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...max(Date.now, context.state.endDate), countsDown: true)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.attributes.exerciseName) · next \(context.state.nextSetDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Color("AccentColor"))
            } compactTrailing: {
                Text(timerInterval: Date.now...max(Date.now, context.state.endDate), countsDown: true)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Color("AccentColor"))
            }
            .keylineTint(Color("AccentColor"))
        }
    }
}
