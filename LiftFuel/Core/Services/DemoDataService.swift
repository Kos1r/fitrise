import Foundation
import SwiftData

/// Realistic sample data: ~10 weeks of Push/Pull training with steady progression,
/// a week of meals, water and body-weight entries. Used for previews, screenshots
/// and the "Load demo data" debug option.
@MainActor
enum DemoDataService {
    static func load(into context: ModelContext, now: Date, calendar: Calendar = .current) {
        SeedService.seedIfNeeded(context)
        let profile = context.profile()
        profile.name = profile.name.isEmpty ? "Alex" : profile.name
        profile.age = 19
        profile.heightCm = 181
        profile.weightKg = 74.6
        profile.gender = .male
        profile.activity = .moderate
        profile.goal = .leanBulk

        loadWorkouts(into: context, now: now, calendar: calendar)
        loadNutrition(into: context, now: now, calendar: calendar)
        loadBodyWeight(into: context, now: now, calendar: calendar)
        loadChat(into: context, now: now)
        context.saveQuietly()
    }

    /// Starting working weights (kg) per exercise, and per-session progression.
    private static let startWeights: [String: (weight: Double, step: Double)] = [
        "incline-chest-press": (50, 1.25),
        "pec-deck": (45, 1.0),
        "shoulder-press": (35, 1.0),
        "shoulder-flyes": (20, 0.5),
        "triceps-pushdowns": (25, 0.75),
        "overhead-triceps-extensions": (20, 0.6),
        "lat-pulldown": (55, 1.25),
        "t-bar-rows": (40, 1.25),
        "pullovers": (35, 0.75),
        "cable-biceps-curls": (20, 0.5),
        "hammer-curls": (18, 0.5),
        "preacher-curls": (22, 0.5)
    ]

    private static func loadWorkouts(into context: ModelContext, now: Date, calendar: Calendar) {
        let schedule = context.scheduleService(calendar: calendar)
        let today = calendar.startOfDay(for: now)
        var sessionIndex: [SplitDay: Int] = [:]
        // Oldest first so progression grows over time.
        for offset in stride(from: 70, through: 1, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let split = schedule.plannedSplit(on: day)
            guard split.isTraining else { continue }
            // Skip roughly one in eight sessions to keep it realistic.
            if (offset * 7) % 8 == 3 { continue }
            let index = sessionIndex[split, default: 0]
            sessionIndex[split] = index + 1

            guard let start = calendar.date(bySettingHour: 17, minute: 30 + (offset % 3) * 5, second: 0, of: day) else { continue }
            let session = WorkoutSession(splitDay: split, startedAt: start)
            context.insert(session)
            var minutes = 0.0
            for (order, exercise) in context.exercises(for: split).enumerated() {
                let log = ExerciseLog(order: order)
                context.insert(log)
                log.exercise = exercise
                log.session = session
                let base = startWeights[exercise.stableID] ?? (30, 0.5)
                // Plateau the last few sessions of pullovers so the deload hint shows up.
                let effectiveIndex = exercise.stableID == "pullovers" ? min(index, 6) : index
                let rawWeight = base.weight + Double(effectiveIndex) * base.step
                let weight = (rawWeight / 1.25).rounded() * 1.25
                let upper = exercise.repRangeUpper
                let lower = exercise.repRangeLower
                for setNumber in 0..<3 {
                    let reps = max(lower, upper - setNumber - (index % 3 == 0 ? 1 : 0))
                    let set = SetEntry(order: setNumber, weight: weight, reps: reps)
                    context.insert(set)
                    set.log = log
                    set.isCompleted = true
                    minutes += 2.5
                    set.completedAt = start.addingTimeInterval(minutes * 60)
                }
            }
            session.endedAt = start.addingTimeInterval(minutes * 60 + 300)
        }
        // Mark PRs retroactively so history shows trophies.
        for exercise in context.allExercises() {
            var history: [StrengthMath.SetPerformance] = []
            for log in WorkoutService.history(for: exercise) {
                for set in log.completedSets {
                    set.isPR = StrengthMath.personalRecord(candidate: set.performance, history: history) != nil
                }
                history.append(contentsOf: log.completedSets.map(\.performance))
            }
        }
    }

    private static func loadNutrition(into context: ModelContext, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let breakfast = [
            FoodItemSnapshot(name: "Oats", quantityDescription: "80 g dry", grams: 80, calories: 300, protein: 11, carbs: 51, fat: 5, fiber: 8),
            FoodItemSnapshot(name: "Whey protein", quantityDescription: "1 scoop", grams: 30, calories: 120, protein: 24, carbs: 3, fat: 1.5, fiber: 0),
            FoodItemSnapshot(name: "Banana", quantityDescription: "1 medium", grams: 118, calories: 105, protein: 1.3, carbs: 27, fat: 0.4, fiber: 3.1),
            FoodItemSnapshot(name: "Whole milk", quantityDescription: "250 ml", grams: 250, calories: 160, protein: 8, carbs: 12, fat: 9, fiber: 0)
        ]
        let lunch = [
            FoodItemSnapshot(name: "Chicken breast", quantityDescription: "200 g cooked", grams: 200, calories: 330, protein: 62, carbs: 0, fat: 7, fiber: 0),
            FoodItemSnapshot(name: "Basmati rice", quantityDescription: "1.5 cups cooked", grams: 240, calories: 310, protein: 6.5, carbs: 68, fat: 0.8, fiber: 1),
            FoodItemSnapshot(name: "Olive oil", quantityDescription: "1 tbsp", grams: 13, calories: 120, protein: 0, carbs: 0, fat: 14, fiber: 0),
            FoodItemSnapshot(name: "Broccoli", quantityDescription: "1 cup", grams: 90, calories: 30, protein: 2.5, carbs: 6, fat: 0.3, fiber: 2.4)
        ]
        let snack = [
            FoodItemSnapshot(name: "Greek yogurt", quantityDescription: "200 g", grams: 200, calories: 190, protein: 20, carbs: 8, fat: 9, fiber: 0),
            FoodItemSnapshot(name: "Honey", quantityDescription: "1 tbsp", grams: 21, calories: 64, protein: 0, carbs: 17, fat: 0, fiber: 0),
            FoodItemSnapshot(name: "Walnuts", quantityDescription: "a handful", grams: 25, calories: 165, protein: 3.8, carbs: 3.5, fat: 16, fiber: 1.7)
        ]
        let dinner = [
            FoodItemSnapshot(name: "Beef mince 10%", quantityDescription: "180 g raw", grams: 180, calories: 320, protein: 36, carbs: 0, fat: 19, fiber: 0),
            FoodItemSnapshot(name: "Pasta", quantityDescription: "120 g dry", grams: 120, calories: 430, protein: 15, carbs: 86, fat: 2, fiber: 4),
            FoodItemSnapshot(name: "Tomato sauce", quantityDescription: "150 g", grams: 150, calories: 70, protein: 2.5, carbs: 12, fat: 1.5, fiber: 3)
        ]

        for offset in 0...6 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            func at(_ hour: Int, _ minute: Int) -> Date {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            }
            NutritionService.logMeal(name: "Oats with whey", mealType: .breakfast, items: breakfast, source: .manual, date: at(8, 5), in: context)
            NutritionService.logMeal(name: "Chicken & rice", mealType: .lunch, items: lunch, confidence: .medium, source: .ai, date: at(13, 10), in: context)
            if offset > 0 {
                NutritionService.logMeal(name: "Yogurt bowl", mealType: .snack, items: snack, source: .preset, date: at(16, 0), in: context)
                NutritionService.logMeal(name: "Bolognese", mealType: .dinner, items: Array(dinner.prefix(offset % 2 == 0 ? 3 : 2)), source: .ai, date: at(19, 30), in: context)
            }
            for hour in [9, 12, 15] {
                NutritionService.addWater(500, on: at(hour, 0), in: context)
            }
        }
        context.insert(MealPreset(name: "Yogurt bowl", mealType: .snack, items: snack))
        context.insert(MealPreset(name: "Oats with whey", mealType: .breakfast, items: breakfast))
    }

    private static func loadBodyWeight(into context: ModelContext, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        for offset in stride(from: 41, through: 0, by: -1) {
            guard offset % 2 == 0 || offset < 7,
                  let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let morning = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: day) else { continue }
            let trend = 73.4 + Double(41 - offset) * 0.03
            let noise = sin(Double(offset) * 1.7) * 0.35
            context.insert(BodyWeightEntry(date: morning, weightKg: ((trend + noise) * 10).rounded() / 10))
        }
    }

    private static func loadChat(into context: ModelContext, now: Date) {
        let existing = (try? context.fetchCount(FetchDescriptor<ChatMessage>())) ?? 0
        guard existing == 0 else { return }
        let user = ChatMessage(role: .user, text: "Chicken breast with rice, olive oil and broccoli for lunch")
        user.createdAt = now.addingTimeInterval(-5 * 3600)
        let card = ChatMessage(role: .assistant, kind: .mealCard, text: "Chicken & rice")
        card.createdAt = now.addingTimeInterval(-5 * 3600 + 5)
        card.mealID = context.meals(on: now).first { $0.name == "Chicken & rice" }?.id
        let reply = ChatMessage(role: .assistant, text: "Logged — about 790 kcal and 71 g protein. You've got roughly 1,600 kcal and 70 g protein left today; a solid dinner plus a yogurt snack gets you there.")
        reply.createdAt = now.addingTimeInterval(-5 * 3600 + 8)
        for message in [user, card, reply] { context.insert(message) }
    }
}
