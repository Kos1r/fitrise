import Foundation
import SwiftData

@Model
final class MealEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var name: String = ""
    var mealTypeRaw: String = MealType.snack.rawValue
    var confidenceRaw: String = EstimateConfidence.high.rawValue
    var sourceRaw: String = MealSource.manual.rawValue
    var isFavorite: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \FoodItem.meal)
    var items: [FoodItem]? = []

    init(date: Date, name: String, mealType: MealType, confidence: EstimateConfidence = .high, source: MealSource) {
        self.id = UUID()
        self.date = date
        self.name = name
        self.mealTypeRaw = mealType.rawValue
        self.confidenceRaw = confidence.rawValue
        self.sourceRaw = source.rawValue
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var confidence: EstimateConfidence { EstimateConfidence(rawValue: confidenceRaw) ?? .high }
    var source: MealSource { MealSource(rawValue: sourceRaw) ?? .manual }

    var orderedItems: [FoodItem] {
        (items ?? []).sorted { $0.order < $1.order }
    }

    var totals: MacroTotals {
        orderedItems.reduce(MacroTotals.zero) { $0 + $1.macros }
    }

    var itemSnapshots: [FoodItemSnapshot] {
        orderedItems.map(\.snapshot)
    }
}

@Model
final class FoodItem {
    var id: UUID = UUID()
    var order: Int = 0
    var name: String = ""
    var quantityDescription: String = ""
    var grams: Double = 0
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var meal: MealEntry?

    init(order: Int, snapshot: FoodItemSnapshot) {
        self.id = UUID()
        self.order = order
        apply(snapshot)
    }

    func apply(_ snapshot: FoodItemSnapshot) {
        name = snapshot.name
        quantityDescription = snapshot.quantityDescription
        grams = snapshot.grams
        calories = snapshot.calories
        protein = snapshot.protein
        carbs = snapshot.carbs
        fat = snapshot.fat
        fiber = snapshot.fiber
    }

    var macros: MacroTotals {
        MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber)
    }

    var snapshot: FoodItemSnapshot {
        FoodItemSnapshot(
            name: name,
            quantityDescription: quantityDescription,
            grams: grams,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber
        )
    }
}

/// User-saved meal for one-tap logging.
@Model
final class MealPreset {
    var id: UUID = UUID()
    var name: String = ""
    var mealTypeRaw: String = MealType.snack.rawValue
    var createdAt: Date = Date.now
    var lastUsedAt: Date?
    var useCount: Int = 0
    /// JSON-encoded `[FoodItemSnapshot]`.
    var itemsJSON: Data = Data()

    init(name: String, mealType: MealType, items: [FoodItemSnapshot]) {
        self.id = UUID()
        self.name = name
        self.mealTypeRaw = mealType.rawValue
        self.itemsJSON = (try? JSONEncoder().encode(items)) ?? Data()
    }

    var mealType: MealType { MealType(rawValue: mealTypeRaw) ?? .snack }

    var items: [FoodItemSnapshot] {
        (try? JSONDecoder().decode([FoodItemSnapshot].self, from: itemsJSON)) ?? []
    }

    var totals: MacroTotals {
        items.reduce(MacroTotals.zero) { $0 + $1.macros }
    }
}

@Model
final class WaterEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var milliliters: Double = 0

    init(date: Date, milliliters: Double) {
        self.id = UUID()
        self.date = date
        self.milliliters = milliliters
    }
}

@Model
final class ChatMessage {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var roleRaw: String = ChatRole.user.rawValue
    var kindRaw: String = ChatMessageKind.text.rawValue
    var text: String = ""
    @Attribute(.externalStorage) var imageData: Data?
    var statusRaw: String = ChatMessageStatus.sent.rawValue
    var errorDescription: String?
    /// For `.mealCard` messages: the logged meal this card represents.
    var mealID: UUID?
    /// Set when the user removed the meal from the card.
    var mealRemoved: Bool = false

    init(role: ChatRole, kind: ChatMessageKind = .text, text: String, imageData: Data? = nil, status: ChatMessageStatus = .sent) {
        self.id = UUID()
        self.createdAt = .now
        self.roleRaw = role.rawValue
        self.kindRaw = kind.rawValue
        self.text = text
        self.imageData = imageData
        self.statusRaw = status.rawValue
    }

    var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .user }
    var kind: ChatMessageKind { ChatMessageKind(rawValue: kindRaw) ?? .text }

    var status: ChatMessageStatus {
        get { ChatMessageStatus(rawValue: statusRaw) ?? .sent }
        set { statusRaw = newValue.rawValue }
    }
}

// MARK: - Value types

struct MacroTotals: Equatable, Codable, Sendable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double

    static let zero = MacroTotals(calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0)

    static func + (lhs: MacroTotals, rhs: MacroTotals) -> MacroTotals {
        MacroTotals(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat,
            fiber: lhs.fiber + rhs.fiber
        )
    }
}

struct FoodItemSnapshot: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var quantityDescription: String
    var grams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double

    enum CodingKeys: String, CodingKey {
        case name, quantityDescription, grams, calories, protein, carbs, fat, fiber
    }

    var macros: MacroTotals {
        MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber)
    }

    static let empty = FoodItemSnapshot(
        name: "", quantityDescription: "", grams: 0, calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0
    )
}
