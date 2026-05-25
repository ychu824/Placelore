import XCTest
@testable import PlaceNotes

final class TimeWindowTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testLabelWhenEndIsToday() {
        let today = Date()
        let window = TimeWindow(endDate: today, lengthDays: 15, firstVisitDate: date(2024, 1, 1))
        XCTAssertEqual(window.label, "Last 15 days")
    }

    func testLabelWhenEndIsHistorical() {
        let end = date(2026, 4, 15)
        let window = TimeWindow(endDate: end, lengthDays: 15, firstVisitDate: date(2024, 1, 1))
        XCTAssertEqual(window.label, "Mar 31 – Apr 15")
    }

    func testStartDateIsEndMinusLength() {
        let end = date(2026, 4, 15)
        let window = TimeWindow(endDate: end, lengthDays: 15, firstVisitDate: date(2024, 1, 1))
        let expectedStart = calendar.date(byAdding: .day, value: -15, to: end)!
        XCTAssertEqual(
            calendar.startOfDay(for: window.startDate),
            calendar.startOfDay(for: expectedStart)
        )
    }

    func testEffectiveLengthClampsToDaysSinceFirstVisit() {
        let today = Date()
        let firstVisit = calendar.date(byAdding: .day, value: -8, to: today)!
        let window = TimeWindow(endDate: today, lengthDays: 15, firstVisitDate: firstVisit)
        XCTAssertEqual(window.effectiveLengthDays, 8)
    }

    func testEffectiveLengthIsFullWhenFirstVisitOlder() {
        let today = Date()
        let firstVisit = calendar.date(byAdding: .day, value: -90, to: today)!
        let window = TimeWindow(endDate: today, lengthDays: 15, firstVisitDate: firstVisit)
        XCTAssertEqual(window.effectiveLengthDays, 15)
    }

    func testEffectiveLengthZeroWhenNoFirstVisit() {
        let window = TimeWindow(endDate: Date(), lengthDays: 15, firstVisitDate: nil)
        XCTAssertEqual(window.effectiveLengthDays, 0)
    }
}
