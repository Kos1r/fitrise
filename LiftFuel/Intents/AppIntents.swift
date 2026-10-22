import AppIntents
import Foundation
import SwiftData

/// "Start my workout" — opens the app and starts today's planned split.
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start my workout"
    static let description = IntentDescription("Starts today's planned Push or Pull workout.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingAction.requestStartWorkout()
        return .result()
    }
}

/// "Log water" — adds water without opening the app.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log water"
    static let description = IntentDescription("Adds a glass of water to today's log.")

    @Parameter(title: "Amount (ml)", default: 250)
    var milliliters: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppContainer.shared.mainContext
        NutritionService.addWater(Double(milliliters), in: context)
        let total = context.water(on: .now)
        let target = context.currentTargets().waterMl
        return .result(dialog: "Logged \(milliliters) ml. You're at \(Int(total)) of \(Int(target)) ml today.")
    }
}

/// "How many calories do I have left?"
struct CaloriesLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Calories left today"
    static let description = IntentDescription("Tells you how many calories and how much protein you still need today.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let summary = NutritionService.summary(on: .now, in: AppContainer.shared.mainContext)
        let calories = Int(summary.remaining.calories.rounded())
        let protein = Int(summary.remaining.protein.rounded())
        let dialog: IntentDialog = calories >= 0
            ? "You have \(calories) kcal and \(max(0, protein)) g of protein left today."
            : "You're \(-calories) kcal over your target today, with \(max(0, protein)) g of protein still to go."
        return .result(value: calories, dialog: dialog)
    }
}

struct LiftFuelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: ["Start my workout in \(.applicationName)", "Start \(.applicationName) workout"],
            shortTitle: "Start workout",
            systemImageName: "dumbbell.fill"
        )
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: ["Log water in \(.applicationName)", "Add water to \(.applicationName)"],
            shortTitle: "Log water",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: CaloriesLeftIntent(),
            phrases: ["How many calories do I have left in \(.applicationName)", "Calories left in \(.applicationName)"],
            shortTitle: "Calories left",
            systemImageName: "flame.fill"
        )
    }
}
