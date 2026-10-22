import Foundation
import SwiftData

/// Daily summary used by the dashboard, widgets and the AI coach (`get_daily_summary`).
struct DailyNutritionSummary: Equatable, Sendable {
    var date: Date
    var eaten: MacroTotals
    var targets: NutritionCalculator.Targets
    var waterMl: Double
    var mealCount: Int

    var remaining: MacroTotals {
        MacroTotals(
            calories: targets.calories - eaten.calories,
            protein: targets.protein - eaten.protein,
            carbs: targets.carbs - eaten.carbs,
            fat: targets.fat - eaten.fat,
            fiber: targets.fiber - eaten.fiber
        )
    }
}

@MainActor
enum NutritionService {
    static func summary(on day: Date, in context: ModelContext) -> DailyNutritionSummary {
        let meals = context.meals(on: day)
        return DailyNutritionSummary(
            date: day,
            eaten: meals.reduce(.zero) { $0 + $1.totals },
            targets: context.currentTargets(),
            waterMl: context.water(on: day),
            mealCount: meals.count
        )
    }

    @discardableResult
    static func logMeal(
        name: String,
        mealType: MealType,
        items: [FoodItemSnapshot],
        confidence: EstimateConfidence = .high,
        source: MealSource,
        date: Date = .now,
        in context: ModelContext
    ) -> MealEntry {
        let meal = MealEntry(date: date, name: name, mealType: mealType, confidence: confidence, source: source)
        context.insert(meal)
        for (index, snapshot) in items.enumerated() {
            let item = FoodItem(order: index, snapshot: snapshot)
            context.insert(item)
            item.meal = meal
        }
        context.saveQuietly()
        WidgetSyncService.update(context: context)
        return meal
    }

    static func replaceItems(of meal: MealEntry, with items: [FoodItemSnapshot], in context: ModelContext) {
        for item in meal.items ?? [] {
            item.meal = nil
            context.delete(item)
        }
        for (index, snapshot) in items.enumerated() {
            let item = FoodItem(order: index, snapshot: snapshot)
            context.insert(item)
            item.meal = meal
        }
        context.saveQuietly()
        WidgetSyncService.update(context: context)
    }

    static func delete(_ meal: MealEntry, in context: ModelContext) {
        context.delete(meal)
        context.saveQuietly()
        WidgetSyncService.update(context: context)
    }

    static func addWater(_ ml: Double, on date: Date = .now, in context: ModelContext) {
        context.insert(WaterEntry(date: date, milliliters: ml))
        context.saveQuietly()
    }

    /// Removes the most recent water entry of the day (undo for the "+250 ml" button).
    static func removeLastWater(on day: Date, in context: ModelContext, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        var descriptor = FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let last = try? context.fetch(descriptor).first {
            context.delete(last)
            context.saveQuietly()
        }
    }

    /// "Log the same as yesterday": copies every meal of `source` day to `target` day.
    @discardableResult
    static func copyMeals(from source: Date, to target: Date, in context: ModelContext, calendar: Calendar = .current) -> Int {
        let meals = context.meals(on: source, calendar: calendar)
        let targetStart = calendar.startOfDay(for: target)
        for meal in meals {
            let time = calendar.dateComponents([.hour, .minute], from: meal.date)
            let date = calendar.date(byAdding: time, to: targetStart) ?? targetStart
            logMeal(name: meal.name, mealType: meal.mealType, items: meal.itemSnapshots, confidence: meal.confidence, source: .copied, date: date, in: context)
        }
        return meals.count
    }

    @discardableResult
    static func log(preset: MealPreset, on date: Date = .now, in context: ModelContext) -> MealEntry {
        preset.useCount += 1
        preset.lastUsedAt = .now
        return logMeal(name: preset.name, mealType: MealType.suggested(for: date), items: preset.items, source: .preset, date: date, in: context)
    }

    static func savePreset(from meal: MealEntry, in context: ModelContext) {
        context.insert(MealPreset(name: meal.name, mealType: meal.mealType, items: meal.itemSnapshots))
        meal.isFavorite = true
        context.saveQuietly()
    }

    /// Distinct recent meals (by name) for one-tap re-logging.
    static func recentMeals(limit: Int = 8, in context: ModelContext) -> [MealEntry] {
        var descriptor = FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 60
        let meals = (try? context.fetch(descriptor)) ?? []
        var seen = Set<String>()
        var result: [MealEntry] = []
        for meal in meals {
            let key = meal.name.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(meal)
            if result.count == limit { break }
        }
        return result
    }

    /// Daily calories/protein for the last `days` days (oldest first), for charts and summaries.
    static func dailyTotals(endingOn day: Date, days: Int, in context: ModelContext, calendar: Calendar = .current) -> [(date: Date, totals: MacroTotals)] {
        let end = calendar.startOfDay(for: day)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: end),
              let endExclusive = calendar.date(byAdding: .day, value: 1, to: end) else { return [] }
        let meals = context.meals(from: start, to: endExclusive)
        var buckets: [Date: MacroTotals] = [:]
        for meal in meals {
            buckets[calendar.startOfDay(for: meal.date), default: .zero] = buckets[calendar.startOfDay(for: meal.date), default: .zero] + meal.totals
        }
        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return (date, buckets[date] ?? .zero)
        }
    }
}
