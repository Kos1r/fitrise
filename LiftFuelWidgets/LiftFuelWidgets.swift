import SwiftUI
import WidgetKit

@main
struct LiftFuelWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        RestTimerLiveActivity()
    }
}

// MARK: - Timeline

struct TodayEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? .placeholder
        // Refresh after midnight so "today" rolls over even if the app isn't opened.
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now.addingTimeInterval(3600)
        let entry = TodayEntry(date: .now, snapshot: snapshotForToday(snapshot))
        completion(Timeline(entries: [entry], policy: .after(midnight.addingTimeInterval(60))))
    }

    /// If the stored snapshot is from a previous day, show the next planned day as today and zero the food.
    private func snapshotForToday(_ snapshot: WidgetSnapshot) -> WidgetSnapshot {
        let calendar = Calendar.current
        guard !calendar.isDateInToday(snapshot.generatedAt) else { return snapshot }
        var updated = snapshot
        if let today = snapshot.upcoming.first(where: { calendar.isDateInToday($0.date) }) {
            updated.todaySplit = today.split
            updated.upcoming = snapshot.upcoming.filter { $0.date > today.date }
        }
        updated.todayCompleted = false
        updated.caloriesEaten = 0
        updated.proteinEaten = 0
        return updated
    }
}

// MARK: - Today widget

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("CardBackground") }
        }
        .configurationDisplayName("Today")
        .description("Today's workout and remaining calories and protein.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    var entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: snapshot.calorieProgress) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text(verbatim: "\(Int(snapshot.caloriesRemaining))")
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(URL(string: "liftfuel://nutrition"))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(snapshot.todaySplit.dayTitle, systemImage: snapshot.todaySplit.symbol)
                    .font(.headline)
                Text("\(Int(snapshot.caloriesRemaining)) kcal left")
                Text("\(Int(snapshot.proteinRemaining)) g protein left")
            }
            .widgetURL(URL(string: "liftfuel://workout"))
        case .accessoryInline:
            Text("\(snapshot.todaySplit.titleString) · \(Int(snapshot.caloriesRemaining)) kcal left")
        case .systemMedium:
            HStack(spacing: 14) {
                workoutColumn
                Divider()
                nutritionColumn
            }
        default:
            workoutColumn
        }
    }

    private var workoutColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: snapshot.todaySplit.symbol)
                    .foregroundStyle(snapshot.todaySplit.color)
                Text("Today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(snapshot.todaySplit.dayTitle)
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.7)
            if snapshot.todayCompleted {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color("AccentColor"))
            } else if snapshot.todaySplit.isTraining {
                Text("\(snapshot.exerciseCount) exercises").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Recover & eat well").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(snapshot.upcoming.prefix(3), id: \.date) { day in
                    VStack(spacing: 2) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.system(size: 9, weight: .semibold))
                        Circle().fill(day.split.color).frame(width: 8, height: 8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: snapshot.todaySplit.isTraining && !snapshot.todayCompleted ? "liftfuel://workout/start" : "liftfuel://workout"))
    }

    private var nutritionColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Left today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            metric(value: "\(Int(snapshot.caloriesRemaining))", unit: "kcal", progress: snapshot.calorieProgress, tint: Color("AccentColor"))
            metric(value: "\(Int(snapshot.proteinRemaining))", unit: "g protein", progress: snapshot.proteinProgress, tint: Color("ProteinColor"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(value: String, unit: String, progress: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.weight(.bold).monospacedDigit())
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            ProgressView(value: progress).tint(tint)
        }
    }
}
