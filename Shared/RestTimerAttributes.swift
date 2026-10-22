import ActivityKit
import Foundation

/// Live Activity / Dynamic Island payload for the rest timer.
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
        var totalSeconds: Int
        var nextSetDescription: String
    }

    var exerciseName: String
}
