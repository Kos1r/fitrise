import Charts
import SwiftData
import SwiftUI

enum ChartRange: String, CaseIterable, Identifiable {
    case month = "1M", quarter = "3M", half = "6M", all = "All"

    var id: String { rawValue }

    func startDate(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .month: calendar.date(byAdding: .month, value: -1, to: now)
        case .quarter: calendar.date(byAdding: .month, value: -3, to: now)
        case .half: calendar.date(byAdding: .month, value: -6, to: now)
        case .all: nil
        }
    }
}

enum ProgressMetric: String, CaseIterable, Identifiable {
    case estimated1RM, topSet

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .estimated1RM: "Est. 1RM"
        case .topSet: "Top set"
        }
    }
}

struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise
    @Environment(\.modelContext) private var modelContext
    @State private var range: ChartRange = .quarter
    @State private var metric: ProgressMetric = .estimated1RM
    @State private var selectedDate: Date?

    private struct Point: Identifiable {
        var id: Date { date }
        var date: Date
        var value: Double
        var volume: Double
        var hasPR: Bool
    }

    private var history: [ExerciseLog] { WorkoutService.history(for: exercise) }

    private var points: [Point] {
        let start = range.startDate(from: .now)
        return history.compactMap { log in
            guard let date = log.session?.startedAt else { return nil }
            if let start, date < start { return nil }
            let value = metric == .estimated1RM ? log.bestEstimated1RM : (log.topSet?.weight ?? 0)
            return Point(date: date, value: value, volume: log.completedVolume, hasPR: log.completedSets.contains(where: \.isPR))
        }
    }

    private var bestSet: SetEntry? {
        history.flatMap(\.completedWorkingSets).max { $0.estimated1RM < $1.estimated1RM }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                headerCard
                statsRow
                progressChart
                volumeChart
                settingsCard
                historyList
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.appBackground)
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        Card {
            HStack(spacing: Spacing.m) {
                MuscleAccent(group: exercise.muscleGroup, size: 52)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(exercise.name).font(.title2.weight(.bold))
                    HStack(spacing: Spacing.xs) {
                        MuscleChip(group: exercise.muscleGroup)
                        Chip(title: exercise.equipment.title, tint: .secondary)
                        SplitBadge(split: exercise.splitDay, compact: true)
                    }
                    if let notes = exercise.notes {
                        Text(notes).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var statsRow: some View {
        Card {
            HStack {
                StatTile(
                    value: bestSet.map { Format.kg($0.estimated1RM.rounded()) } ?? "—",
                    label: "Best est. 1RM",
                    symbol: "bolt.fill",
                    tint: exercise.muscleGroup.color
                )
                StatTile(
                    value: bestSet.map { "\(StrengthMath.formatWeight($0.weight))×\($0.reps)" } ?? "—",
                    label: "Best set",
                    symbol: "trophy.fill",
                    tint: Color("ShouldersColor")
                )
                StatTile(value: "\(history.count)", label: "Sessions", symbol: "calendar", tint: .brand)
            }
        }
    }

    private var progressChart: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    CardHeader(title: "Progress", symbol: "chart.line.uptrend.xyaxis", tint: exercise.muscleGroup.color)
                    Picker("Metric", selection: $metric) {
                        ForEach(ProgressMetric.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if points.count < 2 {
                    EmptyStateView(
                        symbol: "chart.xyaxis.line",
                        title: "Not enough data yet",
                        message: "Log this exercise in two sessions to see your trend."
                    )
                    .frame(height: 200)
                } else {
                    Chart {
                        ForEach(points) { point in
                            AreaMark(x: .value("Date", point.date), y: .value("kg", point.value))
                                .foregroundStyle(LinearGradient(colors: [exercise.muscleGroup.color.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Date", point.date), y: .value("kg", point.value))
                                .foregroundStyle(exercise.muscleGroup.color)
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Date", point.date), y: .value("kg", point.value))
                                .foregroundStyle(point.hasPR ? Color("ShouldersColor") : exercise.muscleGroup.color)
                                .symbolSize(point.hasPR ? 70 : 30)
                        }
                        if let selectedDate, let nearest = nearestPoint(to: selectedDate) {
                            RuleMark(x: .value("Selected", nearest.date))
                                .foregroundStyle(.secondary.opacity(0.4))
                                .annotation(position: .top) {
                                    VStack(spacing: 0) {
                                        Text(Format.kg((nearest.value * 10).rounded() / 10)).font(.caption.weight(.bold))
                                        Text(nearest.date.formatted(.dateTime.day().month())).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(6)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXSelection(value: $selectedDate)
                    .frame(height: 220)
                    .accessibilityLabel("Progress chart")
                }
            }
        }
    }

    private var volumeChart: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Volume per session", symbol: "chart.bar.fill", tint: .brand)
                if points.isEmpty {
                    Text("No sessions in this range.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Chart(points) { point in
                        BarMark(x: .value("Date", point.date, unit: .day), y: .value("Volume", point.volume))
                            .foregroundStyle(Color.brand.gradient)
                            .cornerRadius(4)
                    }
                    .frame(height: 140)
                }
            }
        }
    }

    private var settingsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Settings", symbol: "slider.horizontal.3", tint: .secondary)
                Stepper(value: $exercise.restSeconds, in: 30...300, step: 15) {
                    HStack {
                        Text("Rest timer")
                        Spacer()
                        Text(Format.duration(TimeInterval(exercise.restSeconds))).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $exercise.repRangeLower, in: 1...max(1, exercise.repRangeUpper)) {
                    HStack {
                        Text("Rep range min")
                        Spacer()
                        Text("\(exercise.repRangeLower)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $exercise.repRangeUpper, in: exercise.repRangeLower...30) {
                    HStack {
                        Text("Rep range max")
                        Spacer()
                        Text("\(exercise.repRangeUpper)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Text("When you hit the top of the range on every set, the app suggests adding weight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { modelContext.saveQuietly() }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel("History")
            if history.isEmpty {
                Card {
                    EmptyStateView(symbol: "clock.arrow.circlepath", title: "No history yet", message: "Complete a set of this exercise and it will appear here.")
                }
            }
            ForEach(history.reversed()) { log in
                if let session = log.session {
                    NavigationLink(value: WorkoutRoute.session(session.persistentModelID)) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack {
                                Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month().year()))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("e1RM \(Format.kg(log.bestEstimated1RM.rounded()))")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            FlowSetsView(sets: log.completedSets)
                        }
                        .padding(Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func nearestPoint(to date: Date) -> Point? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

/// Sets rendered as small chips: "60×10", warm-ups dimmed, PRs gold.
struct FlowSetsView: View {
    var sets: [SetEntry]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xs) {
                ForEach(sets) { set in
                    HStack(spacing: 3) {
                        if set.isPR {
                            Image(systemName: "trophy.fill").font(.system(size: 9))
                        }
                        Text("\(set.setType.badge.map { "\($0) " } ?? "")\(StrengthMath.formatWeight(set.weight))×\(set.reps)")
                    }
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, 4)
                    .foregroundStyle(set.isPR ? Color("ShouldersColor") : (set.setType == .warmup ? Color.secondary : Color.primary))
                    .background(Color.cardElevated, in: Capsule())
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}
