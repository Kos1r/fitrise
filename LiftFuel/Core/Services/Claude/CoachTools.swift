import Foundation

/// Tool definitions for the nutrition coach and parsing of their inputs.
enum CoachTools {
    static let logMeal = "log_meal"
    static let dailySummary = "get_daily_summary"

    static var definitions: [JSONValue] {
        [logMealDefinition, dailySummaryDefinition]
    }

    static let logMealSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "meal_name": {"type": "string", "description": "Short name for the whole meal, e.g. \\"Eggs on toast\\""},
        "items": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": {"type": "string", "description": "Food name, e.g. \\"Scrambled eggs\\""},
              "quantity_description": {"type": "string", "description": "Human portion, e.g. \\"2 large eggs\\" or \\"1 cup cooked\\""},
              "grams_estimate": {"type": "number", "description": "Estimated edible weight in grams"},
              "calories": {"type": "number", "description": "kcal"},
              "protein_g": {"type": "number"},
              "carbs_g": {"type": "number"},
              "fat_g": {"type": "number"},
              "fiber_g": {"type": "number"}
            },
            "required": ["name", "quantity_description", "grams_estimate", "calories", "protein_g", "carbs_g", "fat_g", "fiber_g"],
            "additionalProperties": false
          }
        },
        "meal_type": {"type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"]},
        "confidence": {"type": "string", "enum": ["low", "medium", "high"]}
      },
      "required": ["meal_name", "items", "meal_type", "confidence"],
      "additionalProperties": false
    }
    """

    private static var logMealDefinition: JSONValue {
        let schema = (try? JSONValue.parse(logMealSchemaJSON)) ?? .object([:])
        return [
            "name": .string(logMeal),
            "description": """
            Log a meal the user ate (or is eating) to today's food diary. Call once per meal with \
            every food item estimated separately. Only call this when the user says they ate the food \
            or sends a photo of their meal — not when they merely ask about a food. If an estimate would \
            be low confidence, ask a short clarifying question instead of calling this tool.
            """,
            "input_schema": schema,
            "strict": true
        ]
    }

    private static var dailySummaryDefinition: JSONValue {
        [
            "name": .string(dailySummary),
            "description": """
            Get today's nutrition from the app's diary: calories, protein, carbs, fat, fiber and water \
            eaten so far, the daily targets, the remaining amounts, and the list of today's meals. \
            Call this before answering questions about what is left or needed today.
            """,
            "input_schema": .object(["type": "object", "properties": .object([:]), "additionalProperties": false])
        ]
    }
}

/// Validated `log_meal` input.
struct LogMealInput: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        var name: String
        var quantityDescription: String
        var gramsEstimate: Double
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var fiber: Double
    }

    enum ParseError: Error, Equatable, LocalizedError {
        case missingField(String)
        case noItems
        case invalidValue(String)

        var errorDescription: String? {
            switch self {
            case .missingField(let field): "Missing required field: \(field)"
            case .noItems: "items must contain at least one food item"
            case .invalidValue(let field): "Invalid value for \(field)"
            }
        }
    }

    var mealName: String
    var items: [Item]
    var mealType: MealType
    var confidence: EstimateConfidence

    init(mealName: String, items: [Item], mealType: MealType, confidence: EstimateConfidence) {
        self.mealName = mealName
        self.items = items
        self.mealType = mealType
        self.confidence = confidence
    }

    init(json: JSONValue) throws {
        guard let name = json["meal_name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            throw ParseError.missingField("meal_name")
        }
        guard let rawItems = json["items"]?.arrayValue else { throw ParseError.missingField("items") }
        guard !rawItems.isEmpty else { throw ParseError.noItems }

        let mealType = json["meal_type"]?.stringValue.flatMap { MealType(rawValue: $0.lowercased()) }
        // Missing confidence is treated as medium rather than rejecting the call.
        let confidence = json["confidence"]?.stringValue.flatMap { EstimateConfidence(rawValue: $0.lowercased()) } ?? .medium

        var items: [Item] = []
        for raw in rawItems {
            guard let itemName = raw["name"]?.stringValue, !itemName.isEmpty else { throw ParseError.missingField("items.name") }
            func number(_ key: String, required: Bool = true) throws -> Double {
                guard let value = raw[key]?.doubleValue else {
                    if required { throw ParseError.missingField("items.\(key)") }
                    return 0
                }
                guard value.isFinite, value >= 0, value < 20_000 else { throw ParseError.invalidValue("items.\(key)") }
                return value
            }
            items.append(Item(
                name: itemName,
                quantityDescription: raw["quantity_description"]?.stringValue ?? "",
                gramsEstimate: try number("grams_estimate", required: false),
                calories: try number("calories"),
                protein: try number("protein_g"),
                carbs: try number("carbs_g"),
                fat: try number("fat_g"),
                fiber: try number("fiber_g", required: false)
            ))
        }

        self.mealName = name
        self.items = items
        self.mealType = mealType ?? .snack
        self.confidence = confidence
    }

    var snapshots: [FoodItemSnapshot] {
        items.map {
            FoodItemSnapshot(
                name: $0.name,
                quantityDescription: $0.quantityDescription,
                grams: $0.gramsEstimate,
                calories: $0.calories,
                protein: $0.protein,
                carbs: $0.carbs,
                fat: $0.fat,
                fiber: $0.fiber
            )
        }
    }

    var totals: MacroTotals {
        snapshots.reduce(.zero) { $0 + $1.macros }
    }
}

/// Builds tool_result content blocks.
enum ToolResult {
    static func success(id: String, payload: JSONValue) -> JSONValue {
        ["type": "tool_result", "tool_use_id": .string(id), "content": .string(payload.serializedString(sortedKeys: true))]
    }

    static func error(id: String, message: String) -> JSONValue {
        ["type": "tool_result", "tool_use_id": .string(id), "content": .string(message), "is_error": true]
    }

    static func macros(_ totals: MacroTotals) -> JSONValue {
        [
            "calories": JSONValue.rounded(totals.calories, places: 0),
            "protein_g": JSONValue.rounded(totals.protein),
            "carbs_g": JSONValue.rounded(totals.carbs),
            "fat_g": JSONValue.rounded(totals.fat),
            "fiber_g": JSONValue.rounded(totals.fiber)
        ]
    }

    static func summary(_ summary: DailyNutritionSummary, meals: [MealEntry]) -> JSONValue {
        let targets = summary.targets
        let mealList: [JSONValue] = meals.map { meal in
            [
                "time": .string(meal.date.formatted(date: .omitted, time: .shortened)),
                "meal_type": .string(meal.mealType.rawValue),
                "name": .string(meal.name),
                "totals": macros(meal.totals)
            ]
        }
        return [
            "date": .string(summary.date.formatted(date: .complete, time: .omitted)),
            "eaten": macros(summary.eaten),
            "targets": [
                "calories": JSONValue.rounded(targets.calories, places: 0),
                "protein_g": JSONValue.rounded(targets.protein, places: 0),
                "carbs_g": JSONValue.rounded(targets.carbs, places: 0),
                "fat_g": JSONValue.rounded(targets.fat, places: 0),
                "fiber_g": JSONValue.rounded(targets.fiber, places: 0),
                "water_ml": JSONValue.rounded(targets.waterMl, places: 0)
            ],
            "remaining": macros(summary.remaining),
            "water_ml_drunk": JSONValue.rounded(summary.waterMl, places: 0),
            "meals": .array(mealList)
        ]
    }
}
