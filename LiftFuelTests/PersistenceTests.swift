import SwiftData
import XCTest
@testable import LiftFuel

/// Integration tests against an in-memory SwiftData store.
@MainActor
final class PersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = AppContainer.make(inMemory: true)
        SeedService.seedIfNeeded(container.mainContext)
    }

    override func tearDown() async throws {
        container = nil
    }

    func testSeedCreatesOnlyTheFixedLibrary() {
        let exercises = context.allExercises()
        XCTAssertEqual(exercises.count, 12)
        XCTAssertEqual(context.exercises(for: .push).map(\.name), [
            "Incline Chest Press", "Pec Deck", "Shoulder Press", "Shoulder Flyes", "Triceps Pushdowns", "Overhead Triceps Extensions"
        ])
        XCTAssertEqual(context.exercises(for: .pull).map(\.name), [
            "Lat Pulldown", "T-Bar Rows", "Pullovers", "Cable Biceps Curls", "Hammer Curls", "Preacher Curls"
        ])
        XCTAssertEqual(context.exercises(for: .pull).first { $0.stableID == "cable-biceps-curls" }?.notes, "Full range of motion")
    }

    func testSeedIsIdempotentAndRemovesUnknownExercises() {
        context.insert(Exercise(stableID: "bench-press", name: "Bench Press", muscleGroup: .chest, equipment: .barbell, splitDay: .push, sortOrder: 99, restSeconds: 90, repRange: 5...8))
        SeedService.seedIfNeeded(context)
        SeedService.seedIfNeeded(context)
        XCTAssertEqual(context.allExercises().count, 12)
        XCTAssertFalse(context.allExercises().contains { $0.stableID == "bench-press" })
        XCTAssertEqual((try? context.fetchCount(FetchDescriptor<ScheduleDay>())) ?? 0, 7)
    }

    func testDefaultTemplateIsSeeded() {
        XCTAssertEqual(context.weeklyTemplate(), .default)
    }

    func testWorkoutPrefillAndPR() throws {
        // Session 1
        let first = WorkoutService.startSession(split: .pull, in: context, at: Date(timeIntervalSinceNow: -7 * 86_400))
        XCTAssertEqual(first.orderedLogs.count, 6)
        let log = try XCTUnwrap(first.orderedLogs.first)
        XCTAssertEqual(log.exercise?.name, "Lat Pulldown")
        XCTAssertEqual(log.orderedSets.count, 3)
        for set in log.orderedSets {
            set.weight = 60
            set.reps = 10
            XCTAssertNil(WorkoutService.toggleCompletion(of: set, in: context)) // no history → no PR
        }
        WorkoutService.finish(first, in: context)
        XCTAssertEqual(first.orderedLogs.count, 1) // empty logs removed
        XCTAssertEqual(first.totalVolume, 1800)

        // Session 2 pre-fills from session 1
        let second = WorkoutService.startSession(split: .pull, in: context)
        let secondLog = try XCTUnwrap(second.orderedLogs.first)
        XCTAssertEqual(secondLog.orderedSets.map(\.weight), [60, 60, 60])
        XCTAssertEqual(secondLog.orderedSets.map(\.reps), [10, 10, 10])
        XCTAssertNotNil(context.activeSession())

        let heavier = try XCTUnwrap(secondLog.orderedSets.first)
        heavier.weight = 62.5
        XCTAssertEqual(WorkoutService.toggleCompletion(of: heavier, in: context), .estimated1RM)
        XCTAssertTrue(heavier.isPR)

        // Un-completing clears the PR flag.
        XCTAssertNil(WorkoutService.toggleCompletion(of: heavier, in: context))
        XCTAssertFalse(heavier.isPR)
    }

    func testWarmupSetsDoNotCountTowardVolume() throws {
        let session = WorkoutService.startSession(split: .push, in: context)
        let log = try XCTUnwrap(session.orderedLogs.first)
        let sets = log.orderedSets
        sets[0].setType = .warmup
        sets[0].weight = 20
        sets[0].reps = 10
        sets[1].weight = 50
        sets[1].reps = 8
        WorkoutService.toggleCompletion(of: sets[0], in: context)
        WorkoutService.toggleCompletion(of: sets[1], in: context)
        XCTAssertEqual(session.totalVolume, 400)
    }

    func testAddAndDeleteSetRenumbers() throws {
        let session = WorkoutService.startSession(split: .push, in: context)
        let log = try XCTUnwrap(session.orderedLogs.first)
        let added = WorkoutService.addSet(to: log, in: context)
        XCTAssertEqual(log.orderedSets.count, 4)
        XCTAssertEqual(added.order, 3)
        WorkoutService.delete(log.orderedSets[1], in: context)
        XCTAssertEqual(log.orderedSets.map(\.order), [0, 1, 2])
    }

    func testDiscardRemovesSession() {
        let session = WorkoutService.startSession(split: .push, in: context)
        WorkoutService.discard(session, in: context)
        XCTAssertNil(context.activeSession())
        XCTAssertEqual((try? context.fetchCount(FetchDescriptor<SetEntry>())) ?? -1, 0)
    }

    func testMealLoggingAndSummary() {
        let items = [
            FoodItemSnapshot(name: "Chicken", quantityDescription: "200 g", grams: 200, calories: 330, protein: 62, carbs: 0, fat: 7, fiber: 0),
            FoodItemSnapshot(name: "Rice", quantityDescription: "1 cup", grams: 160, calories: 205, protein: 4, carbs: 45, fat: 0.4, fiber: 0.6)
        ]
        let meal = NutritionService.logMeal(name: "Chicken & rice", mealType: .lunch, items: items, source: .ai, in: context)
        let summary = NutritionService.summary(on: .now, in: context)
        XCTAssertEqual(summary.eaten.calories, 535)
        XCTAssertEqual(summary.eaten.protein, 66)
        XCTAssertEqual(summary.remaining.protein, summary.targets.protein - 66)

        NutritionService.delete(meal, in: context)
        XCTAssertEqual(NutritionService.summary(on: .now, in: context).eaten.calories, 0)
        XCTAssertEqual((try? context.fetchCount(FetchDescriptor<FoodItem>())) ?? -1, 0) // cascade
    }

    func testCopyYesterday() throws {
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: .now))
        NutritionService.logMeal(name: "Oats", mealType: .breakfast, items: [FoodItemSnapshot(name: "Oats", quantityDescription: "", grams: 80, calories: 300, protein: 11, carbs: 51, fat: 5, fiber: 8)], source: .manual, date: yesterday, in: context)
        XCTAssertEqual(NutritionService.copyMeals(from: yesterday, to: .now, in: context), 1)
        XCTAssertEqual(context.meals(on: .now).first?.name, "Oats")
    }

    func testCoachHistoryStartsWithUserAndMergesRoles() {
        let older = ChatMessage(role: .assistant, text: "Hi! Ask me anything.")
        older.createdAt = Date(timeIntervalSinceNow: -100)
        let user1 = ChatMessage(role: .user, text: "2 eggs")
        user1.createdAt = Date(timeIntervalSinceNow: -90)
        let reply = ChatMessage(role: .assistant, text: "Logged.")
        reply.createdAt = Date(timeIntervalSinceNow: -80)
        let current = ChatMessage(role: .user, text: "What's left?", imageData: Data([0xFF, 0xD8]))
        for message in [older, user1, reply, current] { context.insert(message) }

        let messages = CoachHistory.apiMessages(upTo: current, in: context)
        XCTAssertEqual(messages.first?["role"]?.stringValue, "user")
        XCTAssertEqual(messages.map { $0["role"]?.stringValue ?? "" }, ["user", "assistant", "user"])
        let lastContent = messages.last?["content"]?.arrayValue ?? []
        XCTAssertEqual(lastContent.first?["type"]?.stringValue, "image")
        XCTAssertEqual(lastContent.last?["text"]?.stringValue, "What's left?")
    }

    func testCoachEngineLogsMealWithMockService() async throws {
        let engine = CoachEngine(service: MockClaudeService(delay: .milliseconds(1)))
        engine.send(text: "2 scrambled eggs, 2 slices of toast with butter and a banana", imageData: nil, in: context)
        for _ in 0..<200 where engine.isResponding {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(engine.isResponding)
        let meals = context.meals(on: .now)
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals.first?.totals.calories, 515)
        let cards = (try? context.fetch(FetchDescriptor<ChatMessage>()))?.filter { $0.kind == .mealCard } ?? []
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.mealID, meals.first?.id)
    }

    func testExportProducesCSV() throws {
        DemoDataService.load(into: context, now: .now)
        let bundle = ExportService.makeBundle(context: context)
        XCTAssertFalse(bundle.sessions.isEmpty)
        let csv = ExportService.workoutCSV(bundle)
        XCTAssertTrue(csv.hasPrefix("date,split,exercise,set,weight_kg,reps,type,pr"))
        XCTAssertEqual(ExportService.csvEscape("a,b"), "\"a,b\"")
    }
}
