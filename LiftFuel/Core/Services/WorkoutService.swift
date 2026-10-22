import Foundation
import SwiftData

/// Workout lifecycle and set logging. All mutations save immediately so an
/// app kill mid-workout never loses data (the active session is restored on relaunch).
@MainActor
enum WorkoutService {
    static let defaultSetCount = 3

    @discardableResult
    static func startSession(split: SplitDay, in context: ModelContext, at date: Date = .now) -> WorkoutSession {
        if let active = context.activeSession() {
            return active
        }
        let session = WorkoutSession(splitDay: split, startedAt: date)
        context.insert(session)

        for (index, exercise) in sortedForWorkout(context.exercises(for: split)).enumerated() {
            let log = ExerciseLog(order: index)
            context.insert(log)
            log.exercise = exercise
            log.session = session
            prefillSets(for: log, exercise: exercise, in: context)
        }
        context.saveQuietly()
        return session
    }

    /// Compound movements first, then isolation, keeping the catalog order within a muscle group.
    static func sortedForWorkout(_ exercises: [Exercise]) -> [Exercise] {
        exercises.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Pre-fills the same number of sets with last session's weight × reps.
    private static func prefillSets(for log: ExerciseLog, exercise: Exercise, in context: ModelContext) {
        let previous = lastCompletedLog(for: exercise, excluding: log.session)?.completedSets ?? []
        if previous.isEmpty {
            for order in 0..<defaultSetCount {
                let set = SetEntry(order: order, weight: 0, reps: exercise.repRangeLower)
                context.insert(set)
                set.log = log
            }
        } else {
            for (order, old) in previous.enumerated() {
                let set = SetEntry(order: order, weight: old.weight, reps: old.reps, setType: old.setType)
                context.insert(set)
                set.log = log
            }
        }
    }

    /// The most recent finished session's log for this exercise that has completed sets.
    static func lastCompletedLog(for exercise: Exercise, excluding session: WorkoutSession?) -> ExerciseLog? {
        (exercise.logs ?? [])
            .filter { log in
                guard let s = log.session, s.endedAt != nil else { return false }
                if let session, s.id == session.id { return false }
                return !log.completedSets.isEmpty
            }
            .max { ($0.session?.startedAt ?? .distantPast) < ($1.session?.startedAt ?? .distantPast) }
    }

    /// Completed logs for this exercise in chronological order (finished sessions only).
    static func history(for exercise: Exercise) -> [ExerciseLog] {
        (exercise.logs ?? [])
            .filter { $0.session?.endedAt != nil && !$0.completedWorkingSets.isEmpty }
            .sorted { ($0.session?.startedAt ?? .distantPast) < ($1.session?.startedAt ?? .distantPast) }
    }

    // MARK: Sets

    @discardableResult
    static func addSet(to log: ExerciseLog, in context: ModelContext) -> SetEntry {
        let sets = log.orderedSets
        let template = sets.last
        let set = SetEntry(
            order: (sets.map(\.order).max() ?? -1) + 1,
            weight: template?.weight ?? 0,
            reps: template?.reps ?? (log.exercise?.repRangeLower ?? 10)
        )
        context.insert(set)
        set.log = log
        context.saveQuietly()
        return set
    }

    static func delete(_ set: SetEntry, in context: ModelContext) {
        let log = set.log
        let deletedID = set.id
        set.log = nil
        context.delete(set)
        // Re-number remaining sets so set numbers stay 1, 2, 3…
        if let log {
            for (index, remaining) in log.orderedSets.filter({ $0.id != deletedID }).enumerated() {
                remaining.order = index
            }
        }
        context.saveQuietly()
    }

    /// Toggles completion. Returns the PR kind when completing a set that beats history.
    @discardableResult
    static func toggleCompletion(of set: SetEntry, in context: ModelContext, at date: Date = .now) -> StrengthMath.PRKind? {
        if set.isCompleted {
            set.isCompleted = false
            set.completedAt = nil
            set.isPR = false
            context.saveQuietly()
            return nil
        }
        set.isCompleted = true
        set.completedAt = date
        let pr = detectPR(for: set)
        set.isPR = pr != nil
        context.saveQuietly()
        return pr
    }

    /// Compares against all completed sets of this exercise in other finished sessions,
    /// plus earlier completed sets in the current session.
    static func detectPR(for set: SetEntry) -> StrengthMath.PRKind? {
        guard let log = set.log, let exercise = log.exercise else { return nil }
        var history: [StrengthMath.SetPerformance] = []
        for otherLog in exercise.logs ?? [] where otherLog.id != log.id {
            guard otherLog.session?.endedAt != nil else { continue }
            history.append(contentsOf: otherLog.completedSets.map(\.performance))
        }
        history.append(contentsOf: log.completedSets.filter { $0.id != set.id && $0.order < set.order }.map(\.performance))
        return StrengthMath.personalRecord(candidate: set.performance, history: history)
    }

    // MARK: Hints

    static func overloadHint(for exercise: Exercise, excluding session: WorkoutSession?, increment: Double) -> Double? {
        guard let last = lastCompletedLog(for: exercise, excluding: session) else { return nil }
        return StrengthMath.overloadSuggestion(
            lastSession: last.completedSets.map(\.performance),
            repRangeUpper: exercise.repRangeUpper,
            increment: increment
        )
    }

    static func isPlateaued(_ exercise: Exercise) -> Bool {
        StrengthMath.isPlateau(sessionBests: history(for: exercise).map(\.bestEstimated1RM))
    }

    // MARK: Finish / discard

    static func finish(_ session: WorkoutSession, in context: ModelContext, at date: Date = .now) {
        for log in session.orderedLogs {
            for set in log.orderedSets where !set.isCompleted {
                context.delete(set)
            }
        }
        for log in session.orderedLogs where log.completedSets.isEmpty {
            context.delete(log)
        }
        session.endedAt = date
        context.saveQuietly()
    }

    static func discard(_ session: WorkoutSession, in context: ModelContext) {
        context.delete(session)
        context.saveQuietly()
    }

    // MARK: Volume per muscle group

    /// Completed working sets per muscle group for sessions inside `interval`.
    static func setsPerMuscleGroup(sessions: [WorkoutSession], in interval: DateInterval) -> [MuscleGroup: Int] {
        var result: [MuscleGroup: Int] = [:]
        for session in sessions where interval.contains(session.startedAt) {
            for log in session.orderedLogs {
                guard let group = log.exercise?.muscleGroup else { continue }
                result[group, default: 0] += log.completedWorkingSets.count
            }
        }
        return result
    }
}
