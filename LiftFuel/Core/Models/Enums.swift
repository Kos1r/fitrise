import SwiftUI

enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest, back, biceps, triceps, shoulders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest: String(localized: "Chest")
        case .back: String(localized: "Back")
        case .biceps: String(localized: "Biceps")
        case .triceps: String(localized: "Triceps")
        case .shoulders: String(localized: "Shoulders")
        }
    }

    var symbol: String {
        switch self {
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.rower"
        case .biceps: "dumbbell.fill"
        case .triceps: "bolt.fill"
        case .shoulders: "figure.arms.open"
        }
    }

    var color: Color {
        switch self {
        case .chest: Color("ChestColor")
        case .back: Color("BackColor")
        case .biceps: Color("BicepsColor")
        case .triceps: Color("TricepsColor")
        case .shoulders: Color("ShouldersColor")
        }
    }

    /// Display order inside a split day.
    var sortIndex: Int {
        switch self {
        case .chest: 0
        case .back: 1
        case .shoulders: 2
        case .triceps: 3
        case .biceps: 4
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Sendable {
    case machine, cable, barbell, dumbbell

    var title: String {
        switch self {
        case .machine: String(localized: "Machine")
        case .cable: String(localized: "Cable")
        case .barbell: String(localized: "Barbell")
        case .dumbbell: String(localized: "Dumbbell")
        }
    }
}

enum SetType: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal, warmup, drop, failure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: String(localized: "Normal")
        case .warmup: String(localized: "Warm-up")
        case .drop: String(localized: "Drop set")
        case .failure: String(localized: "Failure")
        }
    }

    /// One-letter badge shown instead of the set number.
    var badge: String? {
        switch self {
        case .normal: nil
        case .warmup: "W"
        case .drop: "D"
        case .failure: "F"
        }
    }

    var color: Color {
        switch self {
        case .normal: .secondary
        case .warmup: Color("ShouldersColor")
        case .drop: Color("TricepsColor")
        case .failure: Color("ChestColor")
        }
    }

    /// Warm-up sets never count toward volume or PRs.
    var countsAsWorkingSet: Bool { self != .warmup }
}

enum Gender: String, Codable, CaseIterable, Identifiable, Sendable {
    case male, female

    var id: String { rawValue }
    var title: String {
        switch self {
        case .male: String(localized: "Male")
        case .female: String(localized: "Female")
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case sedentary, light, moderate, veryActive

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .veryActive: 1.725
        }
    }

    var title: String {
        switch self {
        case .sedentary: String(localized: "Sedentary")
        case .light: String(localized: "Lightly active")
        case .moderate: String(localized: "Moderately active")
        case .veryActive: String(localized: "Very active")
        }
    }

    var detail: String {
        switch self {
        case .sedentary: String(localized: "Desk job, little movement outside training")
        case .light: String(localized: "On your feet sometimes, 6–8k steps")
        case .moderate: String(localized: "Training 3–5×/week plus an active day")
        case .veryActive: String(localized: "Physical job or 10k+ steps and hard training")
        }
    }
}

enum NutritionGoal: String, Codable, CaseIterable, Identifiable, Sendable {
    case leanBulk, maintain, cut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leanBulk: String(localized: "Lean bulk")
        case .maintain: String(localized: "Maintain")
        case .cut: String(localized: "Cut")
        }
    }

    var detail: String {
        switch self {
        case .leanBulk: String(localized: "Small surplus (~10%) — best for building muscle with minimal fat gain")
        case .maintain: String(localized: "Eat at maintenance — recomp slowly")
        case .cut: String(localized: "Moderate deficit (~17%) — lose fat, keep muscle")
        }
    }

    var symbol: String {
        switch self {
        case .leanBulk: "arrow.up.right"
        case .maintain: "equal"
        case .cut: "arrow.down.right"
        }
    }
}

enum MealType: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: String(localized: "Breakfast")
        case .lunch: String(localized: "Lunch")
        case .dinner: String(localized: "Dinner")
        case .snack: String(localized: "Snack")
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }

    /// A sensible meal type for the given time of day.
    static func suggested(for date: Date, calendar: Calendar = .current) -> MealType {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

enum EstimateConfidence: String, Codable, CaseIterable, Sendable {
    case low, medium, high

    var title: String {
        switch self {
        case .low: String(localized: "Low confidence")
        case .medium: String(localized: "Medium confidence")
        case .high: String(localized: "High confidence")
        }
    }
}

enum MealSource: String, Codable, Sendable {
    case ai, manual, preset, copied
}

enum ChatRole: String, Codable, Sendable {
    case user, assistant
}

enum ChatMessageKind: String, Codable, Sendable {
    case text
    case mealCard
}

enum ChatMessageStatus: String, Codable, Sendable {
    case sent, sending, failed
}
