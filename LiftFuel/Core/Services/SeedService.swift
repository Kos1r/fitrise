import Foundation
import SwiftData

/// The fixed exercise library. Only these exercises exist in the app.
struct ExerciseDefinition: Sendable {
    var stableID: String
    var name: String
    var muscleGroup: MuscleGroup
    var equipment: Equipment
    var splitDay: SplitDay
    var notes: String?
    var restSeconds: Int
    var repRange: ClosedRange<Int>
}

enum ExerciseCatalog {
    static let all: [ExerciseDefinition] = [
        // PUSH — chest, shoulders, triceps
        ExerciseDefinition(stableID: "incline-chest-press", name: "Incline Chest Press", muscleGroup: .chest, equipment: .machine, splitDay: .push, notes: nil, restSeconds: 120, repRange: 6...10),
        ExerciseDefinition(stableID: "pec-deck", name: "Pec Deck", muscleGroup: .chest, equipment: .machine, splitDay: .push, notes: "Squeeze and pause at the middle", restSeconds: 90, repRange: 10...15),
        ExerciseDefinition(stableID: "shoulder-press", name: "Shoulder Press", muscleGroup: .shoulders, equipment: .machine, splitDay: .push, notes: nil, restSeconds: 120, repRange: 6...10),
        ExerciseDefinition(stableID: "shoulder-flyes", name: "Shoulder Flyes", muscleGroup: .shoulders, equipment: .machine, splitDay: .push, notes: "Machine lateral raise", restSeconds: 75, repRange: 12...15),
        ExerciseDefinition(stableID: "triceps-pushdowns", name: "Triceps Pushdowns", muscleGroup: .triceps, equipment: .cable, splitDay: .push, notes: nil, restSeconds: 75, repRange: 10...15),
        ExerciseDefinition(stableID: "overhead-triceps-extensions", name: "Overhead Triceps Extensions", muscleGroup: .triceps, equipment: .cable, splitDay: .push, notes: nil, restSeconds: 75, repRange: 10...15),
        // PULL — back, biceps
        ExerciseDefinition(stableID: "lat-pulldown", name: "Lat Pulldown", muscleGroup: .back, equipment: .cable, splitDay: .pull, notes: nil, restSeconds: 120, repRange: 6...10),
        ExerciseDefinition(stableID: "t-bar-rows", name: "T-Bar Rows", muscleGroup: .back, equipment: .barbell, splitDay: .pull, notes: nil, restSeconds: 120, repRange: 6...10),
        ExerciseDefinition(stableID: "pullovers", name: "Pullovers", muscleGroup: .back, equipment: .machine, splitDay: .pull, notes: nil, restSeconds: 90, repRange: 10...15),
        ExerciseDefinition(stableID: "cable-biceps-curls", name: "Cable Biceps Curls", muscleGroup: .biceps, equipment: .cable, splitDay: .pull, notes: "Full range of motion", restSeconds: 75, repRange: 10...15),
        ExerciseDefinition(stableID: "hammer-curls", name: "Hammer Curls", muscleGroup: .biceps, equipment: .cable, splitDay: .pull, notes: "Cable with rope attachment", restSeconds: 75, repRange: 10...15),
        ExerciseDefinition(stableID: "preacher-curls", name: "Preacher Curls", muscleGroup: .biceps, equipment: .machine, splitDay: .pull, notes: nil, restSeconds: 75, repRange: 8...12)
    ]

    static let ids = Set(all.map(\.stableID))
}

@MainActor
enum SeedService {
    /// Idempotent: safe to call on every launch. Upserts the fixed exercise library,
    /// removes anything that isn't in it, and creates default schedule/profile rows.
    static func seedIfNeeded(_ context: ModelContext) {
        seedExercises(context)
        seedSchedule(context)
        if ((try? context.fetchCount(FetchDescriptor<UserProfile>())) ?? 0) == 0 {
            context.insert(UserProfile())
        }
        if ((try? context.fetchCount(FetchDescriptor<NutritionTargets>())) ?? 0) == 0 {
            context.insert(NutritionTargets())
        }
        try? context.save()
    }

    private static func seedExercises(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var byID: [String: Exercise] = [:]
        for exercise in existing where byID[exercise.stableID] == nil {
            byID[exercise.stableID] = exercise
        }

        for (index, definition) in ExerciseCatalog.all.enumerated() {
            if let exercise = byID[definition.stableID] {
                exercise.name = definition.name
                exercise.muscleGroupRaw = definition.muscleGroup.rawValue
                exercise.equipmentRaw = definition.equipment.rawValue
                exercise.splitDayRaw = definition.splitDay.rawValue
                exercise.notes = definition.notes
                exercise.sortOrder = index
            } else {
                context.insert(Exercise(
                    stableID: definition.stableID,
                    name: definition.name,
                    muscleGroup: definition.muscleGroup,
                    equipment: definition.equipment,
                    splitDay: definition.splitDay,
                    notes: definition.notes,
                    sortOrder: index,
                    restSeconds: definition.restSeconds,
                    repRange: definition.repRange
                ))
            }
        }

        // Only the fixed library may exist (custom exercises are reserved for a future version).
        for exercise in existing where !exercise.isCustom && !ExerciseCatalog.ids.contains(exercise.stableID) {
            context.delete(exercise)
        }
        // Remove duplicates that could appear after a sync merge.
        var seen = Set<String>()
        for exercise in existing.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            if seen.contains(exercise.stableID), !exercise.isCustom {
                context.delete(exercise)
            } else {
                seen.insert(exercise.stableID)
            }
        }
    }

    private static func seedSchedule(_ context: ModelContext) {
        let days = (try? context.fetch(FetchDescriptor<ScheduleDay>())) ?? []
        let present = Set(days.map(\.weekday))
        for weekday in 1...7 where !present.contains(weekday) {
            context.insert(ScheduleDay(weekday: weekday, splitDay: WeeklyTemplate.default.split(forWeekday: weekday)))
        }
    }

    /// Wipes all user data and re-seeds defaults.
    static func resetAllData(_ context: ModelContext) {
        try? context.delete(model: SetEntry.self)
        try? context.delete(model: ExerciseLog.self)
        try? context.delete(model: WorkoutSession.self)
        try? context.delete(model: FoodItem.self)
        try? context.delete(model: MealEntry.self)
        try? context.delete(model: MealPreset.self)
        try? context.delete(model: WaterEntry.self)
        try? context.delete(model: BodyWeightEntry.self)
        try? context.delete(model: ChatMessage.self)
        try? context.delete(model: ScheduleOverride.self)
        try? context.delete(model: ScheduleDay.self)
        try? context.delete(model: NutritionTargets.self)
        try? context.delete(model: UserProfile.self)
        try? context.save()
        seedIfNeeded(context)
    }
}
