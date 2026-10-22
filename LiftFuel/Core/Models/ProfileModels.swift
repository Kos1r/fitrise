import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String = ""
    var genderRaw: String = Gender.male.rawValue
    var age: Int = 19
    var heightCm: Double = 180
    var weightKg: Double = 75
    var activityRaw: String = ActivityLevel.moderate.rawValue
    var goalRaw: String = NutritionGoal.leanBulk.rawValue
    var proteinPerKg: Double = 2.0
    var fatPerKg: Double = 0.9
    var onboardingCompleted: Bool = false
    var createdAt: Date = Date.now

    // Training preferences
    var defaultRestSeconds: Int = 90
    var weightIncrement: Double = 2.5

    // Notifications
    var trainingReminderEnabled: Bool = false
    var reminderHour: Int = 17
    var reminderMinute: Int = 0
    var weeklySummaryEnabled: Bool = true

    // Integrations
    var healthKitEnabled: Bool = false

    init() {}

    var gender: Gender {
        get { Gender(rawValue: genderRaw) ?? .male }
        set { genderRaw = newValue.rawValue }
    }

    var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .moderate }
        set { activityRaw = newValue.rawValue }
    }

    var goal: NutritionGoal {
        get { NutritionGoal(rawValue: goalRaw) ?? .leanBulk }
        set { goalRaw = newValue.rawValue }
    }

    var nutritionInput: NutritionCalculator.Input {
        NutritionCalculator.Input(
            gender: gender,
            age: age,
            heightCm: heightCm,
            weightKg: weightKg,
            activity: activity,
            goal: goal,
            proteinPerKg: proteinPerKg,
            fatPerKg: fatPerKg
        )
    }
}

/// Manual overrides for the automatically calculated targets. `nil` means "use the calculated value".
@Model
final class NutritionTargets {
    var caloriesOverride: Double?
    var proteinOverride: Double?
    var carbsOverride: Double?
    var fatOverride: Double?
    var fiberOverride: Double?
    var waterOverride: Double?

    init() {}

    var overrides: NutritionCalculator.Overrides {
        NutritionCalculator.Overrides(
            calories: caloriesOverride,
            protein: proteinOverride,
            carbs: carbsOverride,
            fat: fatOverride,
            fiber: fiberOverride,
            waterMl: waterOverride
        )
    }

    var hasAnyOverride: Bool {
        [caloriesOverride, proteinOverride, carbsOverride, fatOverride, fiberOverride, waterOverride]
            .contains { $0 != nil }
    }

    func clearOverrides() {
        caloriesOverride = nil
        proteinOverride = nil
        carbsOverride = nil
        fatOverride = nil
        fiberOverride = nil
        waterOverride = nil
    }
}

@Model
final class BodyWeightEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var weightKg: Double = 0

    init(date: Date, weightKg: Double) {
        self.id = UUID()
        self.date = date
        self.weightKg = weightKg
    }
}
