import SwiftData
import SwiftUI

/// This week vs last week: workouts, volume, PRs, average calories/protein vs target.
struct WeeklySummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(DayClock.self) private var clock
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt)
    private var sessions: [WorkoutSession]
    @Query private var scheduleDays: [ScheduleDay]
    @Query private var overrides: [ScheduleOverride]
    @State private var weekOffset = 0

    private var schedule: ScheduleService { ScheduleService(days: scheduleDays, overrides: overrides) }
    private var referenceDate: Date { Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: clock.now) ?? clock.now }
    private var week: DateInterval { schedule.weekInterval(containing: referenceDate) }
    private var weekSessions: [WorkoutSession] { sessions.filter { week.contains($0.startedAt) } }

    private var nutrition: (avgCalories: Double, avgProtein: Double, loggedDays: Int) {
        let days = NutritionService.dailyTotals(endingOn: min(week.end.addingTimeInterval(-1), clock.now), days: 7, in: modelContext)
            .filter { week.contains($0.date) && $0.totals.calories > 0 }
        guard !days.isEmpty else { return (0, 0, 0) }
        let count = Double(days.count)
        return (days.reduce(0) { $0 + $1.totals.calories } / count, days.reduce(0) { $0 + $1.totals.protein } / count, days.count)
    }

    var body: some View {
        let targets = modelContext.currentTargets()
        let food = nutrition
        let planned = schedule.plannedTrainingDays(inWeekContaining: referenceDate)
        let done = schedule.completedDays(inWeekContaining: referenceDate, completedDayKeys: sessions.completedDayKeys())
        let volume = weekSessions.reduce(0) { $0 + $1.totalVolume }
        let prs = weekSessions.reduce(0) { $0 + $1.prCount }

        ScrollView {
            VStack(spacing: Spacing.l) {
                HStack {
                    Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel("Previous week")
                    Spacer()
                    Text("\(week.start.formatted(.dateTime.day().month())) – \(week.end.addingTimeInterval(-1).formatted(.dateTime.day().month()))")
                        .font(.headline)
                    Spacer()
                    Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(weekOffset >= 0)
                        .accessibilityLabel("Next week")
                }

                Card {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        CardHeader(title: "Training", symbol: "dumbbell.fill", tint: Color("PushColor"))
                        HStack {
                            StatTile(value: "\(done)/\(planned)", label: "Workouts", symbol: "checkmark.seal.fill", tint: .brand)
                            StatTile(value: Format.volume(volume), label: "Volume", symbol: "scalemass.fill", tint: Color("PullColor"))
                            StatTile(value: "\(prs)", label: "PRs", symbol: "trophy.fill", tint: Color("ShouldersColor"))
                        }
                    }
                }

                MuscleVolumeCardForWeek(sessions: weekSessions)

                Card {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        CardHeader(title: "Nutrition (daily average)", symbol: "fork.knife", tint: .brand)
                        if food.loggedDays == 0 {
                            Text("No meals logged this week.").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            MacroBar(title: "Calories", eaten: food.avgCalories, target: targets.calories, unit: "kcal", tint: .brand)
                            MacroBar(title: "Protein", eaten: food.avgProtein, target: targets.protein, tint: .protein)
                            Text("Based on \(food.loggedDays) logged days.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        CardHeader(title: "Takeaway", symbol: "sparkles", tint: Color("ShouldersColor"))
                        Text(takeaway(done: done, planned: planned, prs: prs, food: food, targets: targets))
                            .font(.subheadline)
                    }
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.appBackground)
        .navigationTitle("Weekly summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private func takeaway(done: Int, planned: Int, prs: Int, food: (avgCalories: Double, avgProtein: Double, loggedDays: Int), targets: NutritionCalculator.Targets) -> String {
        var parts: [String] = []
        if planned > 0 {
            if done >= planned {
                parts.append(String(localized: "Every planned workout done — great consistency."))
            } else {
                parts.append(String(localized: "\(done) of \(planned) workouts done. Consistency beats intensity — protect your next session."))
            }
        }
        if prs > 0 { parts.append(String(localized: "\(prs) new PRs this week. Progressive overload is working.")) }
        if food.loggedDays > 0 {
            let proteinGap = targets.protein - food.avgProtein
            if proteinGap > 15 {
                parts.append(String(localized: "Protein averaged \(Int(proteinGap)) g under target. An extra shake or a portion of Greek yogurt closes the gap."))
            } else {
                parts.append(String(localized: "Protein was on point."))
            }
            let calorieGap = targets.calories - food.avgCalories
            if calorieGap > 300 {
                parts.append(String(localized: "Calories were about \(Int(calorieGap)) kcal under target — for a lean bulk, add a carb-rich snack around training."))
            }
        }
        return parts.joined(separator: " ")
    }
}

/// Muscle-group sets for a specific list of sessions.
struct MuscleVolumeCardForWeek: View {
    var sessions: [WorkoutSession]

    var body: some View {
        let counts = WorkoutService.setsPerMuscleGroup(sessions: sessions, in: DateInterval(start: .distantPast, end: .distantFuture))
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Sets per muscle", symbol: "chart.bar.fill", tint: Color("PullColor"))
                ForEach(MuscleGroup.allCases.sorted { $0.sortIndex < $1.sortIndex }) { group in
                    let sets = counts[group] ?? 0
                    HStack(spacing: Spacing.m) {
                        Text(group.title).font(.subheadline.weight(.medium)).frame(width: 80, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(group.color.gradient)
                                .frame(width: max(6, proxy.size.width * min(1, Double(sets) / 20)))
                        }
                        .frame(height: 10)
                        Text("\(sets)").font(.subheadline.weight(.semibold).monospacedDigit()).frame(width: 28, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
