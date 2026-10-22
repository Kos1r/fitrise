import Foundation
import SwiftData

/// System prompt for the nutrition coach: fixed guidance plus a compact, real-numbers context block.
enum CoachPrompt {
    static let guidance = """
    You are the nutrition coach inside Lift & Fuel, a training app. The user is a young lifter \
    following a Push/Pull split and wants to build muscle. You help them log food and hit their \
    daily calorie and macro targets.

    Logging food
    - When the user tells you what they ate, or sends a photo of their meal, estimate every item \
    with realistic portions and typical nutrition values, then call log_meal once for that meal.
    - If something that changes the estimate a lot is unclear (portion size, cooking oil, what the \
    food actually is), don't guess: ask one short clarifying question instead, for example "Was \
    the rice about one or two cups?". Don't call log_meal with low confidence.
    - Don't log food the user only asks about ("is a kebab good for bulking?") unless they say they ate it.
    - After a meal is logged, the app shows the user a card with every item, so don't list the items \
    again. Reply in one to three short sentences: total kcal and protein of the meal and what is left today.

    Answering questions
    - When the user asks what they still need today, call get_daily_summary and answer from it.
    - The context below has today's real numbers; use them and always give concrete numbers \
    (kcal and grams). Use metric units.
    - Use the training schedule when it helps, e.g. "you have a Pull day tomorrow, so get some carbs in tonight".

    Style
    - Concise, friendly and practical. Plain sentences; a short bullet list is fine; no headings.
    - Never shame the user about food. Calorie estimates are estimates; say so when it matters.
    - Don't diagnose medical conditions. For medical issues, allergies or eating-disorder concerns, \
    suggest a doctor or registered dietitian.
    """

    @MainActor
    static func system(context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> String {
        guidance + "\n\n" + contextBlock(context: context, now: now, calendar: calendar)
    }

    @MainActor
    static func contextBlock(context: ModelContext, now: Date, calendar: Calendar = .current) -> String {
        let profile = context.profile()
        let summary = NutritionService.summary(on: now, in: context)
        let meals = context.meals(on: now, calendar: calendar)
        let schedule = context.scheduleService(calendar: calendar)
        let today = schedule.plannedDay(on: now)
        let trainedToday = context.completedDayKeys(calendar: calendar).contains(schedule.dayKey(for: now))
        let upcoming = schedule.upcoming(after: now, count: 3)

        return makeContext(
            now: now,
            timeZone: calendar.timeZone,
            profile: profile.nutritionInput,
            summary: summary,
            meals: meals.map { MealLine(time: $0.date, type: $0.mealType, name: $0.name, totals: $0.totals) },
            today: today.split,
            trainedToday: trainedToday,
            upcoming: upcoming.map { ($0.date, $0.split) }
        )
    }

    struct MealLine {
        var time: Date
        var type: MealType
        var name: String
        var totals: MacroTotals
    }

    /// Pure formatter (unit-tested).
    static func makeContext(
        now: Date,
        timeZone: TimeZone,
        profile: NutritionCalculator.Input,
        summary: DailyNutritionSummary,
        meals: [MealLine],
        today: SplitDay,
        trainedToday: Bool,
        upcoming: [(Date, SplitDay)]
    ) -> String {
        let dateStyle = Date.FormatStyle(date: .complete, time: .shortened, timeZone: timeZone).locale(Locale(identifier: "en_GB"))
        let weekday = Date.FormatStyle(timeZone: timeZone).weekday(.wide).locale(Locale(identifier: "en_GB"))
        let time = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone).locale(Locale(identifier: "en_GB"))
        let t = summary.targets
        let e = summary.eaten
        let r = summary.remaining

        var lines: [String] = []
        lines.append("Current context (live data from the app):")
        lines.append("- Now: \(now.formatted(dateStyle)) (\(timeZone.identifier))")
        let todayText = today == .rest ? "Rest day" : "\(today.titleString) day" + (trainedToday ? " (workout done)" : " (not trained yet)")
        let upcomingText = upcoming.map { "\($0.0.formatted(weekday)) \($0.1.titleString)" }.joined(separator: ", ")
        lines.append("- Training: today \(todayText); next: \(upcomingText)")
        lines.append("- Profile: \(profile.gender.rawValue), \(profile.age) y, \(n(profile.heightCm)) cm, \(n(profile.weightKg)) kg, \(profile.activity.title.lowercased()), goal: \(profile.goal.title.lowercased())")
        lines.append("- Daily targets: \(n(t.calories)) kcal, protein \(n(t.protein)) g, carbs \(n(t.carbs)) g, fat \(n(t.fat)) g, fiber \(n(t.fiber)) g, water \(n(t.waterMl)) ml")
        lines.append("- Eaten today: \(n(e.calories)) kcal, protein \(n(e.protein)) g, carbs \(n(e.carbs)) g, fat \(n(e.fat)) g, fiber \(n(e.fiber)) g; water \(n(summary.waterMl)) ml")
        lines.append("- Remaining today: \(n(r.calories)) kcal, protein \(n(r.protein)) g, carbs \(n(r.carbs)) g, fat \(n(r.fat)) g")
        if meals.isEmpty {
            lines.append("- Meals today: none logged yet")
        } else {
            lines.append("- Meals today:")
            for meal in meals {
                lines.append("  - \(meal.time.formatted(time)) \(meal.type.rawValue): \(meal.name) — \(n(meal.totals.calories)) kcal, \(n(meal.totals.protein)) g protein")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func n(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
