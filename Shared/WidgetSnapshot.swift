import Foundation

/// A small, precomputed summary the app writes to the shared App Group so the widgets
/// never need to open the SwiftData store.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct UpcomingDay: Codable, Equatable, Sendable {
        var date: Date
        var split: SplitDay
    }

    var generatedAt: Date
    var todaySplit: SplitDay
    var todayCompleted: Bool
    var exerciseCount: Int
    var upcoming: [UpcomingDay]
    var caloriesEaten: Double
    var caloriesTarget: Double
    var proteinEaten: Double
    var proteinTarget: Double

    var caloriesRemaining: Double { max(0, caloriesTarget - caloriesEaten) }
    var proteinRemaining: Double { max(0, proteinTarget - proteinEaten) }
    var calorieProgress: Double { caloriesTarget > 0 ? min(1, caloriesEaten / caloriesTarget) : 0 }
    var proteinProgress: Double { proteinTarget > 0 ? min(1, proteinEaten / proteinTarget) : 0 }

    static let appGroupID = "group.com.liftfuel.app"
    static let storageKey = "widgetSnapshot.v1"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func load() -> WidgetSnapshot? {
        guard let data = sharedDefaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        WidgetSnapshot.sharedDefaults.set(data, forKey: WidgetSnapshot.storageKey)
    }

    static let placeholder = WidgetSnapshot(
        generatedAt: .now,
        todaySplit: .push,
        todayCompleted: false,
        exerciseCount: 6,
        upcoming: [
            UpcomingDay(date: .now.addingTimeInterval(86_400), split: .pull),
            UpcomingDay(date: .now.addingTimeInterval(172_800), split: .rest),
            UpcomingDay(date: .now.addingTimeInterval(259_200), split: .push)
        ],
        caloriesEaten: 1_840,
        caloriesTarget: 3_050,
        proteinEaten: 112,
        proteinTarget: 150
    )
}
