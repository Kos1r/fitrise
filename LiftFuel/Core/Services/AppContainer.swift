import Foundation
import SwiftData

/// Launch arguments used by UI tests and screenshots.
enum LaunchFlags {
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }
    static var loadDemoData: Bool { ProcessInfo.processInfo.arguments.contains("-demoData") }
    static var skipOnboarding: Bool { ProcessInfo.processInfo.arguments.contains("-skipOnboarding") }
    static var isRunningUnitTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil && !isUITesting }
}

@MainActor
enum AppContainer {
    static let schema = Schema([
        Exercise.self,
        WorkoutSession.self,
        ExerciseLog.self,
        SetEntry.self,
        ScheduleDay.self,
        ScheduleOverride.self,
        UserProfile.self,
        NutritionTargets.self,
        BodyWeightEntry.self,
        MealEntry.self,
        FoodItem.self,
        MealPreset.self,
        WaterEntry.self,
        ChatMessage.self
    ])

    /// The single container shared by the app UI and App Intents.
    static let shared: ModelContainer = make(inMemory: LaunchFlags.isUITesting || LaunchFlags.isRunningUnitTests)

    /// CloudKit sync can be enabled later by switching `cloudKitDatabase` to `.automatic`
    /// (the schema already avoids unique constraints and non-optional relationships).
    static func make(inMemory: Bool) -> ModelContainer {
        let configuration = ModelConfiguration(
            "LiftFuel",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A corrupted or incompatible store must not brick the app: fall back to memory.
            let fallback = ModelConfiguration("LiftFuelFallback", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Unable to create any SwiftData container: \(error)")
            }
        }
    }

    /// Fresh in-memory container with seed data, for previews and tests.
    static func preview(withDemoData: Bool = true) -> ModelContainer {
        let container = make(inMemory: true)
        let context = container.mainContext
        SeedService.seedIfNeeded(context)
        if withDemoData {
            DemoDataService.load(into: context, now: .now)
        }
        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            profile.onboardingCompleted = true
        }
        try? context.save()
        return container
    }
}
