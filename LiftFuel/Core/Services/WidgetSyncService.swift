import Foundation
import SwiftData
import WidgetKit

/// Writes the compact snapshot the widgets read, then asks WidgetKit to reload.
@MainActor
enum WidgetSyncService {
    static func update(context: ModelContext, now: Date = .now) {
        let schedule = context.scheduleService()
        let today = schedule.plannedDay(on: now)
        let summary = NutritionService.summary(on: now, in: context)
        let completed = context.completedDayKeys().contains(schedule.dayKey(for: now))
        let snapshot = WidgetSnapshot(
            generatedAt: now,
            todaySplit: today.split,
            todayCompleted: completed,
            exerciseCount: today.split.isTraining ? context.exercises(for: today.split).count : 0,
            upcoming: schedule.upcoming(after: now, count: 4).map { .init(date: $0.date, split: $0.split) },
            caloriesEaten: summary.eaten.calories,
            caloriesTarget: summary.targets.calories,
            proteinEaten: summary.eaten.protein,
            proteinTarget: summary.targets.protein
        )
        if var previous = WidgetSnapshot.load() {
            previous.generatedAt = now
            if previous == snapshot { return }
        }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
