import XCTest

/// Captures the main screens with demo data. Images are attached to the test result and,
/// when SCREENSHOT_DIR is set (CI passes TEST_RUNNER_SCREENSHOT_DIR), written as PNGs.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: url)
        }
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoData", "-skipOnboarding"] + extra
        app.launch()
        return app
    }

    func testMainScreens() {
        let app = launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        capture(app, "01-home")

        app.swipeUp()
        sleep(1)
        capture(app, "02-home-scrolled")

        app.tabBars.buttons["Calendar"].tap()
        sleep(1)
        capture(app, "03-calendar")

        app.tabBars.buttons["Nutrition"].tap()
        sleep(1)
        capture(app, "04-nutrition")
        app.swipeUp()
        sleep(1)
        capture(app, "05-nutrition-scrolled")

        app.tabBars.buttons["Coach"].tap()
        sleep(1)
        capture(app, "06-coach")

        app.tabBars.buttons["Workout"].tap()
        sleep(1)
        capture(app, "07-workout-hub")

        let push = app.buttons["hub.startPush"]
        if push.waitForExistence(timeout: 3) {
            push.tap()
            sleep(1)
            capture(app, "08-active-workout")
            let complete = app.buttons.matching(identifier: "set.complete").firstMatch
            if complete.exists {
                complete.tap()
                sleep(1)
                capture(app, "09-rest-timer")
            }
            let weight = app.buttons.matching(identifier: "set.weight").element(boundBy: 1)
            if weight.exists {
                weight.tap()
                sleep(1)
                capture(app, "10-keypad")
            }
        }
    }

    func testLightModeAndOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleInterfaceStyle", "Light", "-appearance", "light"]
        app.launch()
        if app.buttons["onboarding.continue"].waitForExistence(timeout: 10) {
            capture(app, "11-onboarding-welcome")
            app.buttons["onboarding.continue"].tap()
            sleep(1)
            capture(app, "12-onboarding-profile")
        }
    }

    func testLightModeHome() {
        let app = launch(["-appearance", "light"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        capture(app, "13-home-light")
        app.tabBars.buttons["Nutrition"].tap()
        sleep(1)
        capture(app, "14-nutrition-light")
    }
}
