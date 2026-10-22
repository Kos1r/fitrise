import XCTest
@testable import LiftFuel

final class StrengthMathTests: XCTestCase {
    typealias P = StrengthMath.SetPerformance

    func testEpley() {
        XCTAssertEqual(StrengthMath.estimated1RM(weight: 100, reps: 10), 133.333, accuracy: 0.01)
        XCTAssertEqual(StrengthMath.estimated1RM(weight: 60, reps: 5), 70, accuracy: 0.001)
        XCTAssertEqual(StrengthMath.estimated1RM(weight: 140, reps: 1), 140)
        XCTAssertEqual(StrengthMath.estimated1RM(weight: 0, reps: 10), 0)
        XCTAssertEqual(StrengthMath.estimated1RM(weight: 50, reps: 0), 0)
    }

    func testNoPRWithoutHistory() {
        XCTAssertNil(StrengthMath.personalRecord(candidate: P(weight: 100, reps: 5), history: []))
    }

    func testEstimated1RMPR() {
        let history = [P(weight: 60, reps: 10), P(weight: 65, reps: 8)]
        XCTAssertEqual(StrengthMath.personalRecord(candidate: P(weight: 67.5, reps: 8), history: history), .estimated1RM)
    }

    func testRepMaxPR() {
        // Best e1RM is from a heavy single; 80×6 beats the best weight at ≥6 reps (75) but not the e1RM.
        let history = [P(weight: 100, reps: 1), P(weight: 75, reps: 6)]
        XCTAssertEqual(StrengthMath.personalRecord(candidate: P(weight: 80, reps: 6), history: history), .repMax)
    }

    func testNotAPR() {
        let history = [P(weight: 60, reps: 10)]
        XCTAssertNil(StrengthMath.personalRecord(candidate: P(weight: 60, reps: 9), history: history))
        XCTAssertNil(StrengthMath.personalRecord(candidate: P(weight: 60, reps: 10), history: history))
    }

    func testWarmupsNeverCount() {
        let history = [P(weight: 60, reps: 10)]
        XCTAssertNil(StrengthMath.personalRecord(candidate: P(weight: 100, reps: 10, setType: .warmup), history: history))
        // A heavy warm-up in history doesn't block a real PR.
        let withWarmup = [P(weight: 60, reps: 10), P(weight: 200, reps: 10, setType: .warmup)]
        XCTAssertEqual(StrengthMath.personalRecord(candidate: P(weight: 62.5, reps: 10), history: withWarmup), .estimated1RM)
    }

    func testVolumeExcludesWarmups() {
        let sets = [P(weight: 20, reps: 10, setType: .warmup), P(weight: 60, reps: 10), P(weight: 60, reps: 8, setType: .drop)]
        XCTAssertEqual(StrengthMath.volume(of: sets), 1080)
    }

    func testOverloadSuggestion() {
        let topOfRange = [P(weight: 60, reps: 12), P(weight: 60, reps: 12), P(weight: 60, reps: 12)]
        XCTAssertEqual(StrengthMath.overloadSuggestion(lastSession: topOfRange, repRangeUpper: 12), 62.5)
        let notYet = [P(weight: 60, reps: 12), P(weight: 60, reps: 11)]
        XCTAssertNil(StrengthMath.overloadSuggestion(lastSession: notYet, repRangeUpper: 12))
        XCTAssertNil(StrengthMath.overloadSuggestion(lastSession: [], repRangeUpper: 12))
        // Warm-ups are ignored.
        let withWarmup = [P(weight: 20, reps: 5, setType: .warmup), P(weight: 60, reps: 12)]
        XCTAssertEqual(StrengthMath.overloadSuggestion(lastSession: withWarmup, repRangeUpper: 12, increment: 1.25), 61.25)
    }

    func testPlateauDetection() {
        XCTAssertTrue(StrengthMath.isPlateau(sessionBests: [90, 100, 100, 99, 100]))
        XCTAssertFalse(StrengthMath.isPlateau(sessionBests: [90, 100, 100, 101, 100]))
        XCTAssertFalse(StrengthMath.isPlateau(sessionBests: [100, 100, 100])) // not enough sessions
    }

    func testFormatWeight() {
        XCTAssertEqual(StrengthMath.formatWeight(60), "60")
        XCTAssertEqual(StrengthMath.formatWeight(42.5), 42.5.formatted(.number.precision(.fractionLength(0...2))))
    }

    func testKeypadBuffer() {
        var buffer = KeypadBuffer(value: 60, allowsDecimal: true)
        buffer.press("4")
        buffer.press("2")
        buffer.press(".")
        buffer.press("5")
        XCTAssertEqual(buffer.value, 42.5)
        buffer.press("5")
        buffer.press("5") // max 2 decimals
        XCTAssertEqual(buffer.text, "42.55")
        buffer.step(by: 2.5)
        XCTAssertEqual(buffer.value, 45.05, accuracy: 0.0001)

        var reps = KeypadBuffer(value: 10, allowsDecimal: false)
        reps.press(".")
        reps.press("8")
        XCTAssertEqual(reps.value, 8)
        reps.step(by: -10)
        XCTAssertEqual(reps.value, 0)
    }

    func testBodyWeightMovingAverage() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = (0..<10).map { (date: start.addingTimeInterval(Double($0) * 86_400), kg: 70.0 + Double($0) * 0.1) }
        let average = BodyWeightMath.movingAverage(entries)
        XCTAssertEqual(average[0].kg, 70.0, accuracy: 0.0001)
        // Day 9 averages days 3…9 → 70.6
        XCTAssertEqual(average[9].kg, 70.6, accuracy: 0.0001)
        // Moving average rises 70.0 → 70.6 over 9 days ≈ 0.47 kg/week.
        XCTAssertEqual(BodyWeightMath.weeklyChange(entries) ?? 0, 0.6 / (9.0 / 7.0), accuracy: 0.01)
    }
}
