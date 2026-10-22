import SwiftUI

/// The three day types of the Push/Pull split. Shared between the app and its widgets.
enum SplitDay: String, Codable, CaseIterable, Identifiable, Sendable {
    case push
    case pull
    case rest

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .rest: "Rest"
        }
    }

    var titleString: String {
        switch self {
        case .push: String(localized: "Push")
        case .pull: String(localized: "Pull")
        case .rest: String(localized: "Rest")
        }
    }

    var dayTitle: String {
        switch self {
        case .push: String(localized: "Push Day")
        case .pull: String(localized: "Pull Day")
        case .rest: String(localized: "Rest Day")
        }
    }

    var shortLabel: String {
        switch self {
        case .push: "PU"
        case .pull: "PL"
        case .rest: "R"
        }
    }

    var symbol: String {
        switch self {
        case .push: "arrow.up.forward.circle.fill"
        case .pull: "arrow.down.backward.circle.fill"
        case .rest: "moon.zzz.fill"
        }
    }

    var color: Color {
        switch self {
        case .push: Color("PushColor")
        case .pull: Color("PullColor")
        case .rest: Color("RestColor")
        }
    }

    var isTraining: Bool { self != .rest }

    /// The two trainable splits, for pickers that start a workout.
    static let trainable: [SplitDay] = [.push, .pull]
}
