import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(DayClock.self) private var clock

    @Query private var scheduleDays: [ScheduleDay]
    @Query private var overrides: [ScheduleOverride]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var finishedSessions: [WorkoutSession]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil })
    private var activeSessions: [WorkoutSession]
    @Query private var profiles: [UserProfile]

    private var schedule: ScheduleService { ScheduleService(days: scheduleDays, overrides: overrides) }
    private var completedKeys: Set<Int> { finishedSessions.completedDayKeys() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.l) {
                    header
                    TodayWorkoutCard(
                        plannedDay: schedule.plannedDay(on: clock.now),
                        activeSession: activeSessions.first,
                        completedToday: finishedSessions.sessions(on: clock.now)
                    )
                    NextUpStrip(days: schedule.upcoming(after: clock.now, count: 7), completedKeys: completedKeys, schedule: schedule)
                    weekStats
                    TodayNutritionCard(day: clock.now)
                    ProgressHintsCard(split: schedule.plannedSplit(on: clock.now))
                    HStack(spacing: Spacing.m) {
                        BodyWeightMiniCard()
                        WeeklySummaryMiniCard()
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xxl)
            }
            .background(Color.appBackground)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(clock.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(greeting)
                .font(.largeTitle.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: clock.now)
        let name = profiles.first?.name ?? ""
        let base: String
        switch hour {
        case 5..<12: base = String(localized: "Good morning")
        case 12..<18: base = String(localized: "Good afternoon")
        default: base = String(localized: "Good evening")
        }
        return name.isEmpty ? base : "\(base), \(name)"
    }

    private var weekStats: some View {
        let streak = schedule.streak(completedDayKeys: completedKeys, today: clock.now)
        let done = schedule.completedDays(inWeekContaining: clock.now, completedDayKeys: completedKeys)
        let planned = schedule.plannedTrainingDays(inWeekContaining: clock.now)
        let weekInterval = schedule.weekInterval(containing: clock.now)
        let weekSessions = finishedSessions.filter { weekInterval.contains($0.startedAt) }
        let prs = weekSessions.reduce(0) { $0 + $1.prCount }
        return Card {
            HStack(spacing: Spacing.m) {
                StatTile(value: "\(streak)", label: "Day streak", symbol: "flame.fill", tint: Color("PushColor"))
                Divider().frame(height: 32)
                StatTile(value: "\(done)/\(planned)", label: "This week", symbol: "checkmark.seal.fill", tint: .brand)
                Divider().frame(height: 32)
                StatTile(value: "\(prs)", label: "PRs this week", symbol: "trophy.fill", tint: Color("ShouldersColor"))
            }
        }
    }
}

// MARK: - Today workout card

struct TodayWorkoutCard: View {
    var plannedDay: PlannedDay
    var activeSession: WorkoutSession?
    var completedToday: [WorkoutSession]

    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query(sort: \Exercise.sortOrder) private var exercises: [Exercise]

    private var split: SplitDay { plannedDay.split }
    private var splitExercises: [Exercise] { exercises.filter { $0.splitDay == split } }
    private var muscleGroups: [MuscleGroup] {
        var seen: [MuscleGroup] = []
        for exercise in splitExercises where !seen.contains(exercise.muscleGroup) { seen.append(exercise.muscleGroup) }
        return seen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack {
                SplitBadge(split: activeSession?.splitDay ?? split)
                if plannedDay.isOverride {
                    Chip(title: String(localized: "Moved"), symbol: "arrow.left.arrow.right", tint: .secondary)
                }
                Spacer()
                Image(systemName: (activeSession?.splitDay ?? split).symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle((activeSession?.splitDay ?? split).color.opacity(0.9))
                    .accessibilityHidden(true)
            }
            content
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if let activeSession {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Workout in progress").font(.title2.weight(.bold))
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("\(Format.duration(activeSession.duration)) · \(activeSession.completedSetCount) sets done")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                router.selectedTab = .workout
            } label: {
                Label("Resume workout", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: activeSession.splitDay.color))
            .accessibilityIdentifier("home.resumeWorkout")
        } else if let done = completedToday.first {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Done for today 💪").font(.title2.weight(.bold))
                Text("\(Format.volume(done.totalVolume)) lifted · \(done.completedSetCount) sets · \(Format.shortDuration(done.duration))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if split.isTraining == false || done.splitDay == split {
                Text("Eat well and sleep — that's where the growth happens.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if split.isTraining {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(split.dayTitle).font(.title.weight(.bold))
                Text("\(splitExercises.count) exercises · \(muscleGroups.map(\.title).joined(separator: " · "))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Button {
                WorkoutLauncher.start(split, context: modelContext, router: router)
            } label: {
                Label(split == .push ? "Start Push Workout" : "Start Pull Workout", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: split.color))
            .accessibilityIdentifier("home.startWorkout")
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Rest Day").font(.title.weight(.bold))
                Text("Recover, eat your protein and sleep well. Feeling fresh? You can still train.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.m) {
                ForEach(SplitDay.trainable) { option in
                    Button {
                        WorkoutLauncher.start(option, context: modelContext, router: router)
                    } label: {
                        Label(option == .push ? "Push" : "Pull", systemImage: option.symbol)
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: option.color))
                    .accessibilityIdentifier(option == .push ? "home.startPush" : "home.startPull")
                }
            }
        }
    }

    private var background: some View {
        let tint = (activeSession?.splitDay ?? split).color
        return ZStack {
            Color.cardBackground
            LinearGradient(
                colors: [tint.opacity(0.32), tint.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Next up strip

struct NextUpStrip: View {
    var days: [PlannedDay]
    var completedKeys: Set<Int>
    var schedule: ScheduleService
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                SectionLabel("Next up")
                Button("Calendar") { router.selectedTab = .calendar }
                    .font(.footnote.weight(.semibold))
            }
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.s) {
                    ForEach(days) { day in
                        DayTile(day: day, isCompleted: completedKeys.contains(schedule.dayKey(for: day.date)))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct DayTile: View {
    var day: PlannedDay
    var isCompleted: Bool

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(day.date.formatted(.dateTime.day()))
                .font(.title3.weight(.bold).monospacedDigit())
            ZStack {
                Circle().fill(day.split.color.opacity(0.18))
                Image(systemName: isCompleted ? "checkmark" : day.split.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(day.split.color)
            }
            .frame(width: 28, height: 28)
            Text(day.split.title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(day.split.color)
        }
        .frame(width: 64)
        .padding(.vertical, Spacing.m)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(day.isOverride ? day.split.color.opacity(0.6) : Color.hairline.opacity(0.6), lineWidth: day.isOverride ? 1.5 : 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(day.date.formatted(.dateTime.weekday(.wide).day().month())): \(day.split.dayTitle)"))
    }
}

// MARK: - Nutrition snapshot

struct TodayNutritionCard: View {
    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @Query private var targetRows: [NutritionTargets]
    @Environment(AppRouter.self) private var router

    init(day: Date) {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= start && $0.date < end })
    }

    private var targets: NutritionCalculator.Targets {
        let input = profiles.first?.nutritionInput ?? UserProfile().nutritionInput
        return NutritionCalculator.targets(for: input, overrides: targetRows.first?.overrides ?? .none)
    }

    private var eaten: MacroTotals { meals.reduce(.zero) { $0 + $1.totals } }

    var body: some View {
        Button {
            router.selectedTab = .nutrition
        } label: {
            Card {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    CardHeader(title: "Nutrition today", symbol: "fork.knife") {
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    HStack(spacing: Spacing.l) {
                        CalorieRing(eaten: eaten.calories, target: targets.calories, size: 112)
                        VStack(spacing: Spacing.m) {
                            MacroBar(title: "Protein", eaten: eaten.protein, target: targets.protein, tint: .protein)
                            MacroBar(title: "Carbs", eaten: eaten.carbs, target: targets.carbs, tint: .carbs)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hints

struct ProgressHintsCard: View {
    var split: SplitDay
    @Query(sort: \Exercise.sortOrder) private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext

    private struct Hint: Identifiable {
        var id: String
        var symbol: String
        var tint: Color
        var title: String
        var detail: String
    }

    private var hints: [Hint] {
        let increment = profiles.first?.weightIncrement ?? 2.5
        let relevant = split.isTraining ? exercises.filter { $0.splitDay == split } : exercises
        var result: [Hint] = []
        for exercise in relevant {
            if let suggestion = WorkoutService.overloadHint(for: exercise, excluding: nil, increment: increment), split.isTraining {
                result.append(Hint(
                    id: "overload-\(exercise.stableID)",
                    symbol: "arrow.up.circle.fill",
                    tint: .brand,
                    title: exercise.name,
                    detail: String(localized: "You hit the top of your rep range — try \(Format.kg(suggestion)) today.")
                ))
            }
            if WorkoutService.isPlateaued(exercise) {
                result.append(Hint(
                    id: "plateau-\(exercise.stableID)",
                    symbol: "exclamationmark.triangle.fill",
                    tint: Color("ShouldersColor"),
                    title: exercise.name,
                    detail: String(localized: "No progress in 4 sessions. Consider a deload week (−10%) or switching to a new rep range.")
                ))
            }
        }
        // Actionable "add weight" notes first; at most two plateau warnings so the card stays short.
        let overload = result.filter { $0.id.hasPrefix("overload") }
        let plateau = result.filter { $0.id.hasPrefix("plateau") }.prefix(2)
        return Array((overload + plateau).prefix(4))
    }

    var body: some View {
        let currentHints = self.hints
        if !currentHints.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    CardHeader(title: "Coach's notes", symbol: "lightbulb.fill", tint: Color("ShouldersColor"))
                    ForEach(currentHints) { hint in
                        HStack(alignment: .top, spacing: Spacing.m) {
                            Image(systemName: hint.symbol)
                                .foregroundStyle(hint.tint)
                                .font(.headline)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hint.title).font(.subheadline.weight(.semibold))
                                Text(hint.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

// MARK: - Mini cards

struct BodyWeightMiniCard: View {
    @Query(sort: \BodyWeightEntry.date) private var entries: [BodyWeightEntry]
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.showBodyWeight = true
        } label: {
            Card {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    CardHeader(title: "Weight", symbol: "scalemass.fill", tint: Color("BicepsColor"))
                    if let last = entries.last {
                        Text(Format.kg(last.weightKg))
                            .font(.statMedium)
                        let trend = BodyWeightMath.weeklyChange(entries.map { ($0.date, $0.weightKg) })
                        Text(trend.map { String(localized: "\($0 >= 0 ? "+" : "")\($0.formatted(.number.precision(.fractionLength(1)))) kg / week") } ?? String(localized: "Log more to see trend"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Log weight").font(.statSmall)
                        Text("Keeps targets accurate").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct WeeklySummaryMiniCard: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.showWeeklySummary = true
        } label: {
            Card {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    CardHeader(title: "Week", symbol: "chart.bar.xaxis", tint: Color("PullColor"))
                    Text("Summary").font(.statMedium)
                    Text("Volume, PRs & macros").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.weeklySummary")
    }
}

#Preview {
    HomeView()
        .modelContainer(AppContainer.preview())
        .environment(AppRouter())
        .environment(DayClock())
        .environment(RestTimerManager())
}
