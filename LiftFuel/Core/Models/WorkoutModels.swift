import Foundation
import SwiftData

// All properties have defaults and to-many relationships are optional so the schema stays
// compatible with a future CloudKit-backed ModelConfiguration.

@Model
final class Exercise {
    /// Stable slug, e.g. "lat-pulldown". Used for seeding/upserts and exports.
    var stableID: String = ""
    var name: String = ""
    var muscleGroupRaw: String = MuscleGroup.chest.rawValue
    var equipmentRaw: String = Equipment.machine.rawValue
    var splitDayRaw: String = SplitDay.push.rawValue
    var notes: String?
    var sortOrder: Int = 0
    var restSeconds: Int = 90
    var repRangeLower: Int = 8
    var repRangeUpper: Int = 12
    var isCustom: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.exercise)
    var logs: [ExerciseLog]? = []

    init(
        stableID: String,
        name: String,
        muscleGroup: MuscleGroup,
        equipment: Equipment,
        splitDay: SplitDay,
        notes: String? = nil,
        sortOrder: Int,
        restSeconds: Int,
        repRange: ClosedRange<Int>
    ) {
        self.stableID = stableID
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.equipmentRaw = equipment.rawValue
        self.splitDayRaw = splitDay.rawValue
        self.notes = notes
        self.sortOrder = sortOrder
        self.restSeconds = restSeconds
        self.repRangeLower = repRange.lowerBound
        self.repRangeUpper = repRange.upperBound
    }

    var muscleGroup: MuscleGroup { MuscleGroup(rawValue: muscleGroupRaw) ?? .chest }
    var equipment: Equipment { Equipment(rawValue: equipmentRaw) ?? .machine }
    var splitDay: SplitDay { SplitDay(rawValue: splitDayRaw) ?? .push }
    var repRangeText: String { "\(repRangeLower)–\(repRangeUpper)" }
}

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var endedAt: Date?
    var splitDayRaw: String = SplitDay.push.rawValue
    var notes: String = ""
    var savedToHealth: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.session)
    var exerciseLogs: [ExerciseLog]? = []

    init(splitDay: SplitDay, startedAt: Date = .now) {
        self.id = UUID()
        self.splitDayRaw = splitDay.rawValue
        self.startedAt = startedAt
    }

    var splitDay: SplitDay { SplitDay(rawValue: splitDayRaw) ?? .push }
    var isActive: Bool { endedAt == nil }

    var orderedLogs: [ExerciseLog] {
        (exerciseLogs ?? []).sorted { $0.order < $1.order }
    }

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }

    /// Volume (kg × reps) of completed working sets.
    var totalVolume: Double {
        orderedLogs.reduce(0) { $0 + $1.completedVolume }
    }

    var completedSetCount: Int {
        orderedLogs.reduce(0) { $0 + $1.completedSets.count }
    }

    var totalSetCount: Int {
        orderedLogs.reduce(0) { $0 + ($1.sets?.count ?? 0) }
    }

    var prCount: Int {
        orderedLogs.reduce(0) { $0 + $1.completedSets.filter(\.isPR).count }
    }
}

@Model
final class ExerciseLog {
    var id: UUID = UUID()
    var order: Int = 0
    var note: String = ""
    var exercise: Exercise?
    var session: WorkoutSession?

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.log)
    var sets: [SetEntry]? = []

    init(order: Int) {
        self.id = UUID()
        self.order = order
    }

    var orderedSets: [SetEntry] {
        (sets ?? []).sorted { $0.order < $1.order }
    }

    var completedSets: [SetEntry] {
        orderedSets.filter(\.isCompleted)
    }

    var completedWorkingSets: [SetEntry] {
        completedSets.filter { $0.setType.countsAsWorkingSet }
    }

    var completedVolume: Double {
        completedWorkingSets.reduce(0) { $0 + $1.volume }
    }

    var bestEstimated1RM: Double {
        completedWorkingSets.map(\.estimated1RM).max() ?? 0
    }

    var topSet: SetEntry? {
        completedWorkingSets.max { lhs, rhs in
            if lhs.weight == rhs.weight { return lhs.reps < rhs.reps }
            return lhs.weight < rhs.weight
        }
    }
}

@Model
final class SetEntry {
    var id: UUID = UUID()
    var order: Int = 0
    var weight: Double = 0
    var reps: Int = 0
    var isCompleted: Bool = false
    var completedAt: Date?
    var setTypeRaw: String = SetType.normal.rawValue
    var isPR: Bool = false
    var log: ExerciseLog?

    init(order: Int, weight: Double, reps: Int, setType: SetType = .normal) {
        self.id = UUID()
        self.order = order
        self.weight = weight
        self.reps = reps
        self.setTypeRaw = setType.rawValue
    }

    var setType: SetType {
        get { SetType(rawValue: setTypeRaw) ?? .normal }
        set { setTypeRaw = newValue.rawValue }
    }

    var volume: Double { weight * Double(reps) }
    var estimated1RM: Double { StrengthMath.estimated1RM(weight: weight, reps: reps) }

    var performance: StrengthMath.SetPerformance {
        StrengthMath.SetPerformance(weight: weight, reps: reps, setType: setType)
    }
}

@Model
final class ScheduleDay {
    /// Calendar weekday: 1 = Sunday … 7 = Saturday.
    var weekday: Int = 1
    var splitDayRaw: String = SplitDay.rest.rawValue

    init(weekday: Int, splitDay: SplitDay) {
        self.weekday = weekday
        self.splitDayRaw = splitDay.rawValue
    }

    var splitDay: SplitDay {
        get { SplitDay(rawValue: splitDayRaw) ?? .rest }
        set { splitDayRaw = newValue.rawValue }
    }
}

/// A one-off change to a single date ("do Push today instead") that leaves the weekly template intact.
@Model
final class ScheduleOverride {
    /// yyyymmdd in the user's calendar, see `ScheduleService.dayKey`.
    var dayKey: Int = 0
    var splitDayRaw: String = SplitDay.rest.rawValue

    init(dayKey: Int, splitDay: SplitDay) {
        self.dayKey = dayKey
        self.splitDayRaw = splitDay.rawValue
    }

    var splitDay: SplitDay {
        get { SplitDay(rawValue: splitDayRaw) ?? .rest }
        set { splitDayRaw = newValue.rawValue }
    }
}
