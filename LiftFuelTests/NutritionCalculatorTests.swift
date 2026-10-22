import XCTest
@testable import LiftFuel

final class NutritionCalculatorTests: XCTestCase {
    private let male19 = NutritionCalculator.Input(
        gender: .male, age: 19, heightCm: 180, weightKg: 75,
        activity: .moderate, goal: .leanBulk
    )

    func testMifflinStJeorMale() {
        // 10·75 + 6.25·180 − 5·19 + 5 = 1785
        XCTAssertEqual(NutritionCalculator.bmr(gender: .male, weightKg: 75, heightCm: 180, age: 19), 1785, accuracy: 0.001)
    }

    func testMifflinStJeorFemale() {
        // 10·60 + 6.25·165 − 5·25 − 161 = 1345.25
        XCTAssertEqual(NutritionCalculator.bmr(gender: .female, weightKg: 60, heightCm: 165, age: 25), 1345.25, accuracy: 0.001)
    }

    func testActivityMultipliers() {
        XCTAssertEqual(NutritionCalculator.tdee(bmr: 1000, activity: .sedentary), 1200, accuracy: 0.001)
        XCTAssertEqual(NutritionCalculator.tdee(bmr: 1000, activity: .light), 1375, accuracy: 0.001)
        XCTAssertEqual(NutritionCalculator.tdee(bmr: 1000, activity: .moderate), 1550, accuracy: 0.001)
        XCTAssertEqual(NutritionCalculator.tdee(bmr: 1000, activity: .veryActive), 1725, accuracy: 0.001)
    }

    func testLeanBulkSurplusIsClampedTo250To400() {
        XCTAssertEqual(NutritionCalculator.goalAdjustment(tdee: 2000, goal: .leanBulk), 250, accuracy: 0.001)
        XCTAssertEqual(NutritionCalculator.goalAdjustment(tdee: 3000, goal: .leanBulk), 300, accuracy: 0.001)
        XCTAssertEqual(NutritionCalculator.goalAdjustment(tdee: 5000, goal: .leanBulk), 400, accuracy: 0.001)
        XCTAssertEqual(NutritionCalculator.goalAdjustment(tdee: 3000, goal: .maintain), 0, accuracy: 0.001)
        XCTAssertEqual(NutritionCalculator.goalAdjustment(tdee: 3000, goal: .cut), -525, accuracy: 0.001)
    }

    func testFullTargetsForDefaultUser() {
        let breakdown = NutritionCalculator.breakdown(for: male19)
        XCTAssertEqual(breakdown.tdee, 2766.75, accuracy: 0.01)
        // TDEE + 10% (276.7) = 3043.4 → rounded to 3040
        XCTAssertEqual(breakdown.targets.calories, 3040)
        XCTAssertEqual(breakdown.targets.protein, 150) // 2.0 g/kg
        // max(0.9·75 = 67.5, 20% of 3040 / 9 = 67.6) → 68
        XCTAssertEqual(breakdown.targets.fat, 68)
        // (3040 − 600 − 612) / 4 = 457
        XCTAssertEqual(breakdown.targets.carbs, 457)
        XCTAssertEqual(breakdown.targets.fiber, 43) // 14 g per 1000 kcal
        XCTAssertEqual(breakdown.targets.waterMl, 2650) // 35 ml/kg, rounded to 50
    }

    func testMacrosAddUpToCalories() {
        let t = NutritionCalculator.targets(for: male19)
        let kcal = t.protein * 4 + t.carbs * 4 + t.fat * 9
        XCTAssertEqual(kcal, t.calories, accuracy: 6) // rounding of grams
    }

    func testFatNeverBelowTwentyPercent() {
        let (_, _, fat) = NutritionCalculator.macros(calories: 4000, weightKg: 60, proteinPerKg: 2, fatPerKg: 0.8)
        XCTAssertGreaterThanOrEqual(fat * 9, 4000 * 0.2 - 9)
    }

    func testCarbsNeverNegative() {
        let (_, carbs, _) = NutritionCalculator.macros(calories: 1000, weightKg: 120, proteinPerKg: 2.2, fatPerKg: 1.0)
        XCTAssertEqual(carbs, 0)
    }

    func testCaloriesOverrideRecomputesMacros() {
        let targets = NutritionCalculator.targets(for: male19, overrides: .init(calories: 2500))
        XCTAssertEqual(targets.calories, 2500)
        XCTAssertEqual(targets.protein, 150)
        XCTAssertEqual(targets.carbs, ((2500 - 600 - targets.fat * 9) / 4).rounded())
    }

    func testProteinOverrideKeepsCaloriesAndAdjustsCarbs() {
        let base = NutritionCalculator.targets(for: male19)
        let targets = NutritionCalculator.targets(for: male19, overrides: .init(protein: 180))
        XCTAssertEqual(targets.calories, base.calories)
        XCTAssertEqual(targets.protein, 180)
        XCTAssertEqual(targets.carbs, base.carbs - 30)
    }

    func testWeightChangeChangesTargets() {
        var heavier = male19
        heavier.weightKg = 80
        XCTAssertGreaterThan(NutritionCalculator.targets(for: heavier).calories, NutritionCalculator.targets(for: male19).calories)
        XCTAssertEqual(NutritionCalculator.targets(for: heavier).protein, 160)
    }
}
