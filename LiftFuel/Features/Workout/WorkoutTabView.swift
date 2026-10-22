import Charts
import SwiftData
import SwiftUI

enum WorkoutRoute: Hashable {
    case exercise(PersistentIdentifier)
    case session(PersistentIdentifier)
    case history
}

/// Workout tab: the active workout if there is one, otherwise the training hub.
struct WorkoutTabView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var activeSessions: [WorkoutSession]
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let session = activeSessions.first {
                    ActiveWorkoutView(session: session)
                } else {
                    WorkoutHubView()
                }
            }
            .navigationDestination(for: WorkoutRoute.self) { route in
                WorkoutRouteView(route: route)
            }
        }
    }
}

struct WorkoutRouteView: View {
    var route: WorkoutRoute
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        switch route {
        case .exercise(let id):
            if let exercise = modelContext.model(for: id) as? Exercise {
                ExerciseDetailView(exercise: exercise)
            }
        case .session(let id):
            if let session = modelContext.model(for: id) as? WorkoutSession {
                SessionDetailView(session: session)
            }
        case .history:
            WorkoutHistoryView()
        }
    }
}

struct WorkoutHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(DayClock.self) private var clock
    @Query(sort: \Exercise.sortOrder) private var exercises: [Exercise]
    @Query private var scheduleDays: [ScheduleDay]
    @Query private var overrides: [ScheduleOverride]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var finishedSessions: [WorkoutSession]

    private var todaySplit: SplitDay { ScheduleService(days: scheduleDays, overrides: overrides).plannedSplit(on: clock.now) }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                startCard
                MuscleVolumeCard(sessions: finishedSessions)
                exerciseLibrary
                recentSessions
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.appBackground)
        .navigationTitle("Workout")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() }
        }
    }

    private var startCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Start a workout", symbol: "play.circle.fill")
                Text(todaySplit.isTraining
                     ? String(localized: "Today is \(todaySplit.dayTitle). Pick it, or swap if you need to.")
                     : String(localized: "Rest day planned — you can still train."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: Spacing.m) {
                    ForEach(SplitDay.trainable) { split in
                        Button {
                            WorkoutLauncher.start(split, context: modelContext, router: router)
                        } label: {
                            VStack(spacing: Spacing.xs) {
                                Image(systemName: split.symbol).font(.title2)
                                Text(split.dayTitle).font(.headline)
                                Text("\(exercises.filter { $0.splitDay == split }.count) exercises")
                                    .font(.caption)
                                    .opacity(0.8)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(split == todaySplit ? AnyButtonStyle(PrimaryButtonStyle(tint: split.color)) : AnyButtonStyle(SecondaryButtonStyle(tint: split.color)))
                        .accessibilityIdentifier(split == .push ? "hub.startPush" : "hub.startPull")
                    }
                }
            }
        }
    }

    private var exerciseLibrary: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel("Exercises")
            ForEach(MuscleGroup.allCases.sorted { $0.sortIndex < $1.sortIndex }) { group in
                let groupExercises = exercises.filter { $0.muscleGroup == group }
                if !groupExercises.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(groupExercises) { exercise in
                            NavigationLink(value: WorkoutRoute.exercise(exercise.persistentModelID)) {
                                ExerciseLibraryRow(exercise: exercise)
                            }
                            .buttonStyle(.plain)
                            if exercise.persistentModelID != groupExercises.last?.persistentModelID {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
        }
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                SectionLabel("History")
                NavigationLink("See all", value: WorkoutRoute.history)
                    .font(.footnote.weight(.semibold))
            }
            if finishedSessions.isEmpty {
                Card {
                    EmptyStateView(
                        symbol: "dumbbell.fill",
                        title: "No workouts yet",
                        message: "Your finished sessions will show up here with volume, sets and PRs."
                    )
                }
            } else {
                ForEach(finishedSessions.prefix(5)) { session in
                    NavigationLink(value: WorkoutRoute.session(session.persistentModelID)) {
                        SessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Type-erased button style so we can pick primary/secondary at runtime.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

struct ExerciseLibraryRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: Spacing.m) {
            MuscleAccent(group: exercise.muscleGroup)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.body.weight(.semibold))
                Text("\(exercise.equipment.title) · \(exercise.splitDay.titleString) · \(exercise.repRangeText) reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let best = WorkoutService.history(for: exercise).map(\.bestEstimated1RM).max(), best > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Format.kg(best.rounded())).font(.subheadline.weight(.semibold).monospacedDigit())
                    Text("est. 1RM").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .contentShape(Rectangle())
    }
}

struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: Spacing.m) {
            VStack(spacing: 0) {
                Text(session.startedAt.formatted(.dateTime.day()))
                    .font(.title3.weight(.bold).monospacedDigit())
                Text(session.startedAt.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
            }
            .foregroundStyle(session.splitDay.color)
            .frame(width: 48, height: 48)
            .background(session.splitDay.color.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(session.splitDay.dayTitle).font(.body.weight(.semibold))
                    if session.prCount > 0 { PRBadge() }
                }
                Text("\(Format.volume(session.totalVolume)) · \(session.completedSetCount) sets · \(Format.shortDuration(session.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(Spacing.m)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Sets per muscle group this week vs a 10–20 set "productive range" guide.
struct MuscleVolumeCard: View {
    var sessions: [WorkoutSession]
    @Environment(DayClock.self) private var clock

    private struct MuscleSets: Identifiable {
        var group: MuscleGroup
        var sets: Int
        var id: MuscleGroup { group }
    }

    private var data: [MuscleSets] {
        let interval = ScheduleService().weekInterval(containing: clock.now)
        let counts = WorkoutService.setsPerMuscleGroup(sessions: sessions, in: interval)
        return MuscleGroup.allCases.sorted { $0.sortIndex < $1.sortIndex }.map { MuscleSets(group: $0, sets: counts[$0] ?? 0) }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Weekly sets per muscle", symbol: "chart.bar.fill", tint: Color("PullColor"))
                Chart {
                    RuleMark(x: .value("Target", 10))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    ForEach(data) { item in
                        BarMark(
                            x: .value("Sets", item.sets),
                            y: .value("Muscle", item.group.title)
                        )
                        .foregroundStyle(item.group.color.gradient)
                        .cornerRadius(6)
                        .annotation(position: .trailing) {
                            Text("\(item.sets)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
                .chartXScale(domain: 0...max(20, (data.map(\.sets).max() ?? 0) + 2))
                .chartXAxis(.hidden)
                .frame(height: 180)
                Text("Aim for roughly 10–20 hard sets per muscle per week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
