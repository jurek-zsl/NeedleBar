import XCTest
@testable import NeedleBarCore

final class ClockTimerServiceTests: XCTestCase {
    func testDurationComponents() throws {
        let duration = try TimerDuration(totalSeconds: 5_490)

        XCTAssertEqual(duration.hours, 1)
        XCTAssertEqual(duration.minutes, 31)
        XCTAssertEqual(duration.seconds, 30)
        XCTAssertEqual(duration.displayText, "1 hour 31 minutes 30 seconds")
    }

    func testDurationBounds() throws {
        XCTAssertThrowsError(try TimerDuration(totalSeconds: 0))
        XCTAssertNoThrow(try TimerDuration(totalSeconds: TimerDuration.maximumSeconds))
        XCTAssertThrowsError(try TimerDuration(totalSeconds: TimerDuration.maximumSeconds + 1))
    }

    func testDisplayTextOmitsEmptyComponents() throws {
        XCTAssertEqual(try TimerDuration(totalSeconds: 30).displayText, "30 seconds")
        XCTAssertEqual(try TimerDuration(totalSeconds: 300).displayText, "5 minutes")
        XCTAssertEqual(try TimerDuration(totalSeconds: 3_600).displayText, "1 hour")
    }
}
