import Foundation

/// Pure strength-training math: estimated 1RM, PR detection, progression hints.
enum StrengthMath {
    struct SetPerformance: Equatable, Sendable {
        var weight: Double
        var reps: Int
        var setType: SetType = .normal

        var isWorking: Bool { setType.countsAsWorkingSet && weight > 0 && reps > 0 }
        var estimated1RM: Double { StrengthMath.estimated1RM(weight: weight, reps: reps) }
    }

    enum PRKind: String, Equatable, Sendable {
        /// Best estimated one-rep max ever.
        case estimated1RM
        /// Heaviest weight ever lifted for this many reps (or more).
        case repMax

        var title: String {
            switch self {
            case .estimated1RM: String(localized: "New est. 1RM")
            case .repMax: String(localized: "Rep PR")
            }
        }
    }

    /// Epley formula: 1RM = w × (1 + reps / 30). A single rep is the 1RM itself.
    static func estimated1RM(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    /// Returns the PR kind if `candidate` beats every set in `history`.
    /// No history means no PR (the first session establishes the baseline).
    /// Warm-up sets never count, neither as candidate nor as history.
    static func personalRecord(candidate: SetPerformance, history: [SetPerformance]) -> PRKind? {
        guard candidate.isWorking else { return nil }
        let working = history.filter(\.isWorking)
        guard !working.isEmpty else { return nil }

        let epsilon = 0.0001
        let bestE1RM = working.map(\.estimated1RM).max() ?? 0
        if candidate.estimated1RM > bestE1RM + epsilon {
            return .estimated1RM
        }
        // Best weight previously lifted for at least this many reps.
        let bestAtReps = working.filter { $0.reps >= candidate.reps }.map(\.weight).max()
        if let bestAtReps, candidate.weight > bestAtReps + epsilon {
            return .repMax
        }
        if bestAtReps == nil {
            // Never done this many reps before — a rep PR as long as the weight is meaningful
            // (at least the heaviest weight used for fewer reps).
            let heaviest = working.map(\.weight).max() ?? 0
            if candidate.weight >= heaviest - epsilon {
                return .repMax
            }
        }
        return nil
    }

    /// "Try +2.5 kg today" — if every working set last time hit the top of the rep range.
    /// Returns the suggested new weight, or nil if no increase is suggested.
    static func overloadSuggestion(lastSession: [SetPerformance], repRangeUpper: Int, increment: Double = 2.5) -> Double? {
        let working = lastSession.filter(\.isWorking)
        guard !working.isEmpty, repRangeUpper > 0 else { return nil }
        guard working.allSatisfy({ $0.reps >= repRangeUpper }) else { return nil }
        guard let heaviest = working.map(\.weight).max() else { return nil }
        return heaviest + increment
    }

    /// Plateau: in the last `window` sessions, none of the later sessions beat the first one.
    /// `sessionBests` is the best e1RM per session in chronological order.
    static func isPlateau(sessionBests: [Double], window: Int = 4) -> Bool {
        guard window >= 2, sessionBests.count >= window else { return false }
        let recent = Array(sessionBests.suffix(window))
        guard let baseline = recent.first, baseline > 0 else { return false }
        return recent.dropFirst().allSatisfy { $0 <= baseline + 0.0001 }
    }

    static func volume(of sets: [SetPerformance]) -> Double {
        sets.filter(\.isWorking).reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    /// Formats 42.5 as "42.5" and 60.0 as "60".
    static func formatWeight(_ weight: Double) -> String {
        if weight.rounded() == weight {
            return String(Int(weight))
        }
        return weight.formatted(.number.precision(.fractionLength(0...2)))
    }
}
