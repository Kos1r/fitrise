import XCTest

@MainActor
final class WorkoutFlowUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(demo: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding"]
        if demo { app.launchArguments.append("-demoData") }
        app.launch()
        return app
    }

    /// Start a workout from Home in at most two taps (works on training and rest days).
    private func startWorkout(_ app: XCUIApplication) {
        let start = app.buttons["home.startWorkout"]
        let startPush = app.buttons["home.startPush"]
        if start.waitForExistence(timeout: 5) {
            start.tap()
        } else {
            XCTAssertTrue(startPush.waitForExistence(timeout: 5), "No start button on Home")
            startPush.tap()
        }
        XCTAssertTrue(app.buttons["workout.finish"].waitForExistence(timeout: 5), "Active workout did not open")
    }

    func testStartLogAndFinishWorkout() {
        let app = launch()
        startWorkout(app)

        // Edit weight with the custom keypad: tap weight → type 45 → Done.
        let weightCell = app.buttons.matching(identifier: "set.weight").firstMatch
        XCTAssertTrue(weightCell.waitForExistence(timeout: 3))
        weightCell.tap()
        XCTAssertTrue(app.buttons["keypad.done"].waitForExistence(timeout: 3))
        app.buttons["keypad.4"].tap()
        app.buttons["keypad.5"].tap()
        app.buttons["keypad.done"].tap()

        // Log a set: one tap on the checkmark.
        let complete = app.buttons.matching(identifier: "set.complete").firstMatch
        complete.tap()
        XCTAssertTrue(app.buttons["Skip rest"].waitForExistence(timeout: 3), "Rest timer should start after completing a set")

        // Finish (some sets incomplete → confirmation).
        app.buttons["workout.finish"].tap()
        let confirm = app.buttons["workout.finishConfirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        XCTAssertTrue(app.staticTexts["Workout complete"].waitForExistence(timeout: 5))
        app.buttons["summary.done"].tap()

        // Back on the training hub (no active workout any more).
        XCTAssertTrue(app.buttons["hub.startPush"].waitForExistence(timeout: 5))
    }

    func testAddSetAndDiscard() {
        let app = launch()
        startWorkout(app)
        // The first exercise starts with 3 sets; adding one shows a 4th set row.
        // (Counting all rows is unreliable because List renders rows lazily.)
        let fourthSet = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Set 4,")).firstMatch
        XCTAssertFalse(fourthSet.exists)
        app.buttons.matching(identifier: "workout.addSet").firstMatch.tap()
        XCTAssertTrue(fourthSet.waitForExistence(timeout: 3))

        // Discard via the button at the bottom of the list.
        let discard = app.buttons["workout.discard"]
        for _ in 0..<8 where !discard.isHittable {
            app.swipeUp()
        }
        discard.tap()
        let confirm = app.buttons.matching(identifier: "workout.discardConfirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["hub.startPush"].waitForExistence(timeout: 5))
    }

    func testCoachLogsMealWithMockService() {
        let app = launch()
        app.tabBars.buttons["Coach"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "coach.input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("2 scrambled eggs, 2 slices of toast with butter and a banana")
        app.buttons["coach.send"].tap()
        XCTAssertTrue(app.buttons["mealCard.confirm"].waitForExistence(timeout: 10), "Meal card should appear")
        app.buttons["mealCard.confirm"].tap()

        app.tabBars.buttons["Nutrition"].tap()
        let meal = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Eggs on toast")).firstMatch
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
    }
}
