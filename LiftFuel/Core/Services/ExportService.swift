import Foundation
import SwiftData

/// Exports all training and nutrition data as JSON (complete) and CSV (spreadsheet-friendly).
@MainActor
enum ExportService {
    struct ExportBundle: Codable {
        struct SessionRow: Codable {
            var date: Date
            var endedAt: Date?
            var split: String
            var exercises: [ExerciseRow]
        }
        struct ExerciseRow: Codable {
            var id: String
            var name: String
            var sets: [SetRow]
        }
        struct SetRow: Codable {
            var weightKg: Double
            var reps: Int
            var type: String
            var isPR: Bool
        }
        struct MealRow: Codable {
            var date: Date
            var name: String
            var type: String
            var source: String
            var items: [FoodItemSnapshot]
        }
        struct WeightRow: Codable {
            var date: Date
            var kg: Double
        }

        var exportedAt: Date
        var appVersion: String
        var sessions: [SessionRow]
        var meals: [MealRow]
        var bodyWeight: [WeightRow]
    }

    static func makeBundle(context: ModelContext) -> ExportBundle {
        let sessions = context.finishedSessions().reversed().map { session in
            ExportBundle.SessionRow(
                date: session.startedAt,
                endedAt: session.endedAt,
                split: session.splitDayRaw,
                exercises: session.orderedLogs.map { log in
                    ExportBundle.ExerciseRow(
                        id: log.exercise?.stableID ?? "",
                        name: log.exercise?.name ?? "",
                        sets: log.completedSets.map { ExportBundle.SetRow(weightKg: $0.weight, reps: $0.reps, type: $0.setTypeRaw, isPR: $0.isPR) }
                    )
                }
            )
        }
        let meals = ((try? context.fetch(FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []).map {
            ExportBundle.MealRow(date: $0.date, name: $0.name, type: $0.mealTypeRaw, source: $0.sourceRaw, items: $0.itemSnapshots)
        }
        let weights = context.bodyWeights().map { ExportBundle.WeightRow(date: $0.date, kg: $0.weightKg) }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return ExportBundle(exportedAt: .now, appVersion: version, sessions: Array(sessions), meals: meals, bodyWeight: weights)
    }

    /// Writes JSON + two CSVs to a temporary folder and returns their URLs.
    static func export(context: ModelContext) throws -> [URL] {
        let bundle = makeBundle(context: context)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LiftFuelExport", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonURL = folder.appendingPathComponent("lift-fuel-export.json")
        try encoder.encode(bundle).write(to: jsonURL)

        let setsURL = folder.appendingPathComponent("workout-sets.csv")
        try workoutCSV(bundle).write(to: setsURL, atomically: true, encoding: .utf8)

        let mealsURL = folder.appendingPathComponent("food-log.csv")
        try mealsCSV(bundle).write(to: mealsURL, atomically: true, encoding: .utf8)

        return [jsonURL, setsURL, mealsURL]
    }

    static func workoutCSV(_ bundle: ExportBundle) -> String {
        let iso = ISO8601DateFormatter()
        var rows = ["date,split,exercise,set,weight_kg,reps,type,pr"]
        for session in bundle.sessions {
            for exercise in session.exercises {
                for (index, set) in exercise.sets.enumerated() {
                    rows.append([
                        iso.string(from: session.date), session.split, csvEscape(exercise.name), "\(index + 1)",
                        StrengthMath.formatWeight(set.weightKg), "\(set.reps)", set.type, set.isPR ? "yes" : "no"
                    ].joined(separator: ","))
                }
            }
        }
        return rows.joined(separator: "\n")
    }

    static func mealsCSV(_ bundle: ExportBundle) -> String {
        let iso = ISO8601DateFormatter()
        var rows = ["date,meal_type,meal,item,quantity,grams,kcal,protein_g,carbs_g,fat_g,fiber_g"]
        for meal in bundle.meals {
            for item in meal.items {
                rows.append([
                    iso.string(from: meal.date), meal.type, csvEscape(meal.name), csvEscape(item.name), csvEscape(item.quantityDescription),
                    number(item.grams), number(item.calories), number(item.protein), number(item.carbs), number(item.fat), number(item.fiber)
                ].joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }

    static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
