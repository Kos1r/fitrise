import Foundation
import Observation

enum AppTab: String, Hashable, CaseIterable {
    case home, workout, calendar, nutrition, coach
}

/// Shallow navigation state shared across tabs.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var showSettings = false
    var showWeeklySummary = false
    var showBodyWeight = false
    /// Shown after finishing a workout; lives here because the active-workout view disappears on finish.
    var finishedSummary: WorkoutSummary?
    /// Set by App Intents / notifications; consumed by RootView.
    var pendingStartWorkout = false

    func openWorkout() {
        selectedTab = .workout
    }
}

/// Lightweight, cross-process hand-off from App Intents (which may run before the UI exists).
enum PendingAction {
    private static let key = "pendingAction.startWorkout"

    static func requestStartWorkout() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static func consumeStartWorkout() -> Bool {
        let value = UserDefaults.standard.bool(forKey: key)
        if value { UserDefaults.standard.removeObject(forKey: key) }
        return value
    }
}
