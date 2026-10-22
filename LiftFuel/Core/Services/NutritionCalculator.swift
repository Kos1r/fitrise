import Foundation

/// Pure nutrition formulas. No state, no side effects — fully unit-tested.
enum NutritionCalculator {
    struct Input: Equatable, Sendable {
        var gender: Gender
        var age: Int
        var heightCm: Double
        var weightKg: Double
        var activity: ActivityLevel
        var goal: NutritionGoal
        var proteinPerKg: Double = 2.0
        var fatPerKg: Double = 0.9
    }

    struct Targets: Equatable, Codable, Sendable {
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var fiber: Double
        var waterMl: Double
    }

    struct Overrides: Equatable, Sendable {
        var calories: Double?
        var protein: Double?
        var carbs: Double?
        var fat: Double?
        var fiber: Double?
        var waterMl: Double?

        static let none = Overrides()
    }

    /// Full breakdown, useful for the "how we calculated this" explanation.
    struct Breakdown: Equatable, Sendable {
        var bmr: Double
        var tdee: Double
        var goalAdjustment: Double
        var targets: Targets
    }

    static let kcalPerGramProtein = 4.0
    static let kcalPerGramCarbs = 4.0
    static let kcalPerGramFat = 9.0
    static let minimumFatShare = 0.20
    static let fiberPer1000Kcal = 14.0
    static let waterMlPerKg = 35.0

    /// Mifflin–St Jeor basal metabolic rate in kcal/day.
    static func bmr(gender: Gender, weightKg: Double, heightCm: Double, age: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch gender {
        case .male: return base + 5
        case .female: return base - 161
        }
    }

    static func tdee(bmr: Double, activity: ActivityLevel) -> Double {
        bmr * activity.multiplier
    }

    /// Calorie change applied for the goal, in kcal/day (positive = surplus).
    static func goalAdjustment(tdee: Double, goal: NutritionGoal) -> Double {
        switch goal {
        case .leanBulk:
            // ~10% surplus, kept inside the 250–400 kcal lean-bulk window.
            return min(max(tdee * 0.10, 250), 400)
        case .maintain:
            return 0
        case .cut:
            // ~17.5% deficit (middle of the 15–20% range).
            return -tdee * 0.175
        }
    }

    static func breakdown(for input: Input) -> Breakdown {
        let basal = Self.bmr(gender: input.gender, weightKg: input.weightKg, heightCm: input.heightCm, age: input.age)
        let expenditure = Self.tdee(bmr: basal, activity: input.activity)
        let adjustment = Self.goalAdjustment(tdee: expenditure, goal: input.goal)
        let calories = Self.roundTo(expenditure + adjustment, step: 10)
        let split = Self.macros(calories: calories, weightKg: input.weightKg, proteinPerKg: input.proteinPerKg, fatPerKg: input.fatPerKg)
        let targets = Targets(
            calories: calories,
            protein: split.protein,
            carbs: split.carbs,
            fat: split.fat,
            fiber: Self.fiber(calories: calories),
            waterMl: Self.water(weightKg: input.weightKg)
        )
        return Breakdown(bmr: basal, tdee: expenditure, goalAdjustment: adjustment, targets: targets)
    }

    static func targets(for input: Input, overrides: Overrides = .none) -> Targets {
        apply(overrides, to: breakdown(for: input).targets, weightKg: input.weightKg, proteinPerKg: input.proteinPerKg, fatPerKg: input.fatPerKg)
    }

    /// Splits calories into protein / fat / carbs (grams).
    static func macros(calories: Double, weightKg: Double, proteinPerKg: Double, fatPerKg: Double) -> (protein: Double, carbs: Double, fat: Double) {
        let protein = (weightKg * proteinPerKg).rounded()
        let fatFromBodyweight = weightKg * fatPerKg
        let fatFloor = calories * minimumFatShare / kcalPerGramFat
        let fat = max(fatFromBodyweight, fatFloor).rounded()
        let remaining = calories - protein * kcalPerGramProtein - fat * kcalPerGramFat
        let carbs = max(0, remaining / kcalPerGramCarbs).rounded()
        return (protein, carbs, fat)
    }

    static func fiber(calories: Double) -> Double {
        (calories / 1000 * fiberPer1000Kcal).rounded()
    }

    static func water(weightKg: Double) -> Double {
        roundTo(weightKg * waterMlPerKg, step: 50)
    }

    /// Applies manual overrides. If calories are overridden but carbs are not,
    /// carbs are recomputed to fill the remaining calories.
    static func apply(_ overrides: Overrides, to calculated: Targets, weightKg: Double, proteinPerKg: Double, fatPerKg: Double) -> Targets {
        var result = calculated
        if let calories = overrides.calories {
            result.calories = calories
            let split = Self.macros(calories: calories, weightKg: weightKg, proteinPerKg: proteinPerKg, fatPerKg: fatPerKg)
            result.protein = split.protein
            result.fat = split.fat
            result.carbs = split.carbs
            result.fiber = Self.fiber(calories: calories)
        }
        if let protein = overrides.protein { result.protein = protein }
        if let fat = overrides.fat { result.fat = fat }
        if overrides.carbs == nil, overrides.protein != nil || overrides.fat != nil {
            let remaining = result.calories - result.protein * kcalPerGramProtein - result.fat * kcalPerGramFat
            result.carbs = max(0, remaining / kcalPerGramCarbs).rounded()
        }
        if let carbs = overrides.carbs { result.carbs = carbs }
        if let fiber = overrides.fiber { result.fiber = fiber }
        if let water = overrides.waterMl { result.waterMl = water }
        return result
    }

    static func roundTo(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }
}
