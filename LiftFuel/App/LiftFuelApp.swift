import SwiftData
import SwiftUI

@main
struct LiftFuelApp: App {
    @State private var router = AppRouter()
    @State private var restTimer = RestTimerManager()
    @State private var clock = DayClock()
    @State private var coach: CoachEngine

    private let container: ModelContainer

    init() {
        container = AppContainer.shared
        let service: ClaudeServicing = LaunchFlags.isUITesting ? MockClaudeService() : ClaudeService()
        _coach = State(initialValue: CoachEngine(service: service))

        let context = container.mainContext
        SeedService.seedIfNeeded(context)
        if LaunchFlags.loadDemoData {
            DemoDataService.load(into: context, now: .now)
        }
        if LaunchFlags.skipOnboarding {
            context.profile().onboardingCompleted = true
            context.saveQuietly()
        }
        // Installs the foreground-presentation delegate early.
        _ = NotificationService.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(restTimer)
                .environment(clock)
                .environment(coach)
        }
        .modelContainer(container)
    }
}
