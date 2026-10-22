import Foundation
import SwiftData

extension ScheduleService {
    /// Builds the schedule from @Query results so views stay reactive.
    init(days: [ScheduleDay], overrides: [ScheduleOverride], calendar: Calendar = .current) {
        var map = WeeklyTemplate.default.days
        for day in days { map[day.weekday] = day.splitDay }
        let overrideMap = Dictionary(overrides.map { ($0.dayKey, $0.splitDay) }, uniquingKeysWith: { _, last in last })
        self.init(template: WeeklyTemplate(days: map), overrides: overrideMap, calendar: calendar)
    }
}

extension Array where Element == WorkoutSession {
    func completedDayKeys(calendar: Calendar = .current) -> Set<Int> {
        Set(filter { $0.endedAt != nil }.map { ScheduleService.dayKey(for: $0.startedAt, calendar: calendar) })
    }

    func sessions(on day: Date, calendar: Calendar = .current) -> [WorkoutSession] {
        filter { $0.endedAt != nil && calendar.isDate($0.startedAt, inSameDayAs: day) }
    }
}

@MainActor
enum ScheduleEditor {
    /// Sets a one-off split for a date. Passing the template's own split removes the override.
    static func setSplit(_ split: SplitDay, on date: Date, context: ModelContext) {
        let schedule = context.scheduleService()
        let key = schedule.dayKey(for: date)
        let existing = (try? context.fetch(FetchDescriptor<ScheduleOverride>(predicate: #Predicate { $0.dayKey == key }))) ?? []
        existing.forEach { context.delete($0) }
        if split != schedule.templateSplit(on: date) {
            context.insert(ScheduleOverride(dayKey: key, splitDay: split))
        }
        context.saveQuietly()
        WidgetSyncService.update(context: context)
    }

    static func resetOverride(on date: Date, context: ModelContext) {
        setSplit(context.scheduleService().templateSplit(on: date), on: date, context: context)
    }

    /// Swaps the planned splits of two dates (e.g. "do tomorrow's Pull today").
    static func swap(_ first: Date, _ second: Date, context: ModelContext) {
        let schedule = context.scheduleService()
        let a = schedule.plannedSplit(on: first)
        let b = schedule.plannedSplit(on: second)
        setSplit(b, on: first, context: context)
        setSplit(a, on: second, context: context)
    }

    static func setTemplate(weekday: Int, split: SplitDay, context: ModelContext) {
        let days = (try? context.fetch(FetchDescriptor<ScheduleDay>(predicate: #Predicate { $0.weekday == weekday }))) ?? []
        if let day = days.first {
            day.splitDay = split
            days.dropFirst().forEach { context.delete($0) }
        } else {
            context.insert(ScheduleDay(weekday: weekday, splitDay: split))
        }
        context.saveQuietly()
        let profile = context.profile()
        NotificationService.shared.scheduleTrainingReminders(
            template: context.weeklyTemplate(),
            hour: profile.reminderHour,
            minute: profile.reminderMinute,
            enabled: profile.trainingReminderEnabled
        )
        WidgetSyncService.update(context: context)
    }
}
