import XCTest
@testable import PlaceNotes

final class CurrentlyAtCardFormattersTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testElapsedUnderOneMinuteReadsJustArrived() {
        let now = base.addingTimeInterval(45)
        XCTAssertEqual(
            CurrentlyAtFormatter.elapsed(arrivalDate: base, now: now),
            String(localized: "Just arrived")
        )
    }

    func testElapsedAtFiftyNineSecondsStillJustArrived() {
        let now = base.addingTimeInterval(59)
        XCTAssertEqual(
            CurrentlyAtFormatter.elapsed(arrivalDate: base, now: now),
            String(localized: "Just arrived")
        )
    }

    func testElapsedAtOneMinuteShowsMinutes() {
        let now = base.addingTimeInterval(60)
        let expected = String(format: String(localized: "Arrived %lldm ago"), 1)
        XCTAssertEqual(CurrentlyAtFormatter.elapsed(arrivalDate: base, now: now), expected)
    }

    func testElapsedAtFiftyNineMinutesShowsMinutes() {
        let now = base.addingTimeInterval(59 * 60)
        let expected = String(format: String(localized: "Arrived %lldm ago"), 59)
        XCTAssertEqual(CurrentlyAtFormatter.elapsed(arrivalDate: base, now: now), expected)
    }

    func testElapsedAtOneHourShowsHoursAndMinutes() {
        let now = base.addingTimeInterval(3600 + 720)   // 1h 12m
        let expected = String(format: String(localized: "Arrived %lldh %lldm ago"), 1, 12)
        XCTAssertEqual(CurrentlyAtFormatter.elapsed(arrivalDate: base, now: now), expected)
    }

    func testElapsedAtTwentyThreeHoursShowsHoursAndMinutes() {
        let now = base.addingTimeInterval(23 * 3600 + 59 * 60)
        let expected = String(format: String(localized: "Arrived %lldh %lldm ago"), 23, 59)
        XCTAssertEqual(CurrentlyAtFormatter.elapsed(arrivalDate: base, now: now), expected)
    }
}
