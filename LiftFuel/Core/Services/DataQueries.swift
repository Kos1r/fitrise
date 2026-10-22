import Foundation
import SwiftData

/// Typed fetch helpers. Views mostly use @Query; services and the coach use these.
@MainActor
extension ModelContext {
    func profile() -> UserProfile {
        if let existing = try? fetch(FetchDescriptor<UserProfile>()).first {
            return existing
        }
        let profile = UserProfile()
        insert(profile)
        return profile
    }

    func targetOverrides() -> NutritionTargets {
        if let existing = try? fetch(FetchDescriptor<NutritionTargets>()).first {
            return existing
        }
        let targets = NutritionTargets()
        insert(targets)
        return targets
    }

    func currentTargets() -> NutritionCalculator.Targets {
        NutritionCalculator.targets(for: profile().nutritionInput, overrides: targetOverrides().overrides)
    }

    func weeklyTemplate() -> WeeklyTemplate {
        let days = (try? fetch(FetchDescriptor<ScheduleDay>())) ?? []
        guard !days.isEmpty else { return .default }
        var map = WeeklyTemplate.default.days
        for day in days { map[day.weekday] = day.splitDay }
        return WeeklyTemplate(days: map)
    }

    func scheduleOverrides() -> [Int: SplitDay] {
        let overrides = (try? fetch(FetchDescriptor<ScheduleOverride>())) ?? []
        return Dictionary(overrides.map { ($0.dayKey, $0.splitDay) }, uniquingKeysWith: { _, last in last })
    }

    func scheduleService(calendar: Calendar = .current) -> ScheduleService {
        ScheduleService(template: weeklyTemplate(), overrides: scheduleOverrides(), calendar: calendar)
    }

    func activeSession() -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    func finishedSessions() -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? fetch(descriptor)) ?? []
    }

    func exercises(for split: SplitDay) -> [Exercise] {
        let raw = split.rawValue
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.splitDayRaw == raw },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? fetch(descriptor)) ?? []
    }

    func allExercises() -> [Exercise] {
        (try? fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    func completedDayKeys(calendar: Calendar = .current) -> Set<Int> {
        Set(finishedSessions().map { ScheduleService.dayKey(for: $0.startedAt, calendar: calendar) })
    }

    func meals(on day: Date, calendar: Calendar = .current) -> [MealEntry] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? fetch(descriptor)) ?? []
    }

    func meals(from start: Date, to end: Date) -> [MealEntry] {
        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? fetch(descriptor)) ?? []
    }

    func totals(on day: Date, calendar: Calendar = .current) -> MacroTotals {
        meals(on: day, calendar: calendar).reduce(MacroTotals.zero) { $0 + $1.totals }
    }

    func water(on day: Date, calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let descriptor = FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        return ((try? fetch(descriptor)) ?? []).reduce(0) { $0 + $1.milliliters }
    }

    func meal(id: UUID) -> MealEntry? {
        var descriptor = FetchDescriptor<MealEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    func bodyWeights() -> [BodyWeightEntry] {
        (try? fetch(FetchDescriptor<BodyWeightEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
    }

    func saveQuietly() {
        do {
            try save()
        } catch {
            assertionFailure("SwiftData save failed: \(error)")
        }
    }
}
