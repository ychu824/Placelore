import XCTest
@testable import PlaceNotes

final class VisitTests: XCTestCase {

    // MARK: - Duration

    func testDurationWithDeparture() {
        let arrival = Date()
        let departure = arrival.addingTimeInterval(90 * 60) // 90 minutes
        let visit = Visit(arrivalDate: arrival, departureDate: departure)
        XCTAssertEqual(visit.durationMinutes, 90)
    }

    func testDurationWithoutDepartureUsesNow() {
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let preferredArrival = now.addingTimeInterval(-30 * 60)
        let arrival = preferredArrival < startOfToday ? startOfToday : preferredArrival
        let visit = Visit(arrivalDate: arrival, departureDate: nil)
        let expectedMinutes = Int(Date().timeIntervalSince(arrival) / 60)
        XCTAssertGreaterThanOrEqual(visit.durationMinutes, max(0, expectedMinutes - 1))
        XCTAssertLessThanOrEqual(visit.durationMinutes, expectedMinutes + 1)
    }

    func testDurationNeverNegative() {
        let arrival = Date().addingTimeInterval(60 * 60) // 1 hour in the future
        let departure = Date() // now
        let visit = Visit(arrivalDate: arrival, departureDate: departure)
        XCTAssertEqual(visit.durationMinutes, 0)
    }

    // MARK: - Time of Day

    func testTimeOfDayMorning() {
        let visit = makeVisit(hour: 8)
        XCTAssertEqual(visit.timeOfDay, .morning)
    }

    func testTimeOfDayAfternoon() {
        let visit = makeVisit(hour: 14)
        XCTAssertEqual(visit.timeOfDay, .afternoon)
    }

    func testTimeOfDayEvening() {
        let visit = makeVisit(hour: 19)
        XCTAssertEqual(visit.timeOfDay, .evening)
    }

    func testTimeOfDayNight() {
        let visit = makeVisit(hour: 23)
        XCTAssertEqual(visit.timeOfDay, .night)
    }

    func testTimeOfDayEarlyMorningIsNight() {
        let visit = makeVisit(hour: 3)
        XCTAssertEqual(visit.timeOfDay, .night)
    }

    func testTimeOfDayBoundaryMorningStart() {
        let visit = makeVisit(hour: 5)
        XCTAssertEqual(visit.timeOfDay, .morning)
    }

    func testTimeOfDayBoundaryAfternoonStart() {
        let visit = makeVisit(hour: 12)
        XCTAssertEqual(visit.timeOfDay, .afternoon)
    }

    func testTimeOfDayBoundaryEveningStart() {
        let visit = makeVisit(hour: 17)
        XCTAssertEqual(visit.timeOfDay, .evening)
    }

    func testTimeOfDayBoundaryNightStart() {
        let visit = makeVisit(hour: 21)
        XCTAssertEqual(visit.timeOfDay, .night)
    }

    // MARK: - Active State

    func testIsActiveWhenNoDeparture() {
        let visit = Visit(arrivalDate: Date(), departureDate: nil)
        XCTAssertTrue(visit.isActive)
    }

    func testNotActiveWhenDepartureSet() {
        let visit = Visit(arrivalDate: Date(), departureDate: Date())
        XCTAssertFalse(visit.isActive)
    }

    // MARK: - Confidence

    func testConfidenceDefaultsToMedium() {
        let visit = Visit(arrivalDate: Date())
        XCTAssertEqual(visit.confidence, .medium)
    }

    func testConfidenceRoundTrips() {
        let visit = Visit(arrivalDate: Date())
        visit.confidence = .high
        XCTAssertEqual(visit.confidence, .high)
        XCTAssertEqual(visit.confidenceRaw, "High")

        visit.confidence = .low
        XCTAssertEqual(visit.confidence, .low)
        XCTAssertEqual(visit.confidenceRaw, "Low")
    }

    func testConfidenceFallsBackForInvalidRaw() {
        let visit = Visit(arrivalDate: Date())
        visit.confidenceRaw = "garbage"
        XCTAssertEqual(visit.confidence, .medium)
    }

    func testMedianAccuracyMetersDefaultsToNil() {
        let visit = Visit(arrivalDate: Date())
        XCTAssertNil(visit.medianAccuracyMeters)
    }

    // MARK: - durationString

    func testDurationStringSubHourMinutes() {
        let visit = Visit(
            arrivalDate: Date(timeIntervalSince1970: 1_700_000_000),
            departureDate: Date(timeIntervalSince1970: 1_700_000_000 + 45 * 60)
        )
        XCTAssertEqual(visit.durationString, "45m")
    }

    func testDurationStringExactHours() {
        let visit = Visit(
            arrivalDate: Date(timeIntervalSince1970: 1_700_000_000),
            departureDate: Date(timeIntervalSince1970: 1_700_000_000 + 60 * 60)
        )
        XCTAssertEqual(visit.durationString, "1h")
    }

    func testDurationStringHoursAndMinutes() {
        let visit = Visit(
            arrivalDate: Date(timeIntervalSince1970: 1_700_000_000),
            departureDate: Date(timeIntervalSince1970: 1_700_000_000 + 75 * 60)
        )
        XCTAssertEqual(visit.durationString, "1h 15m")
    }

    func testDurationStringZero() {
        let visit = Visit(
            arrivalDate: Date(timeIntervalSince1970: 1_700_000_000),
            departureDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(visit.durationString, "0m")
    }

    // MARK: - Stranded visits (no departureDate, past day)

    func testDurationStrandedPastDayReturnsZero() {
        let arrival = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let visit = Visit(arrivalDate: arrival, departureDate: nil)
        XCTAssertEqual(visit.durationMinutes, 0)
        XCTAssertEqual(visit.durationString, "0m")
    }

    func testEffectiveDurationUsesCapWhenDepartureMissing() {
        let arrival = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let cap = arrival.addingTimeInterval(45 * 60)
        let visit = Visit(arrivalDate: arrival, departureDate: nil)
        XCTAssertEqual(visit.effectiveDurationMinutes(cappedAt: cap), 45)
        XCTAssertEqual(visit.effectiveDurationString(cappedAt: cap), "45m")
    }

    func testEffectiveDurationPrefersDepartureOverCap() {
        let arrival = Date(timeIntervalSince1970: 1_700_000_000)
        let departure = arrival.addingTimeInterval(20 * 60)
        let cap = arrival.addingTimeInterval(60 * 60)
        let visit = Visit(arrivalDate: arrival, departureDate: departure)
        XCTAssertEqual(visit.effectiveDurationMinutes(cappedAt: cap), 20)
    }

    func testEffectiveDurationTodayUsesNowWhenNoCap() {
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let preferredArrival = now.addingTimeInterval(-15 * 60)
        let arrival = preferredArrival < startOfToday ? startOfToday : preferredArrival
        let visit = Visit(arrivalDate: arrival, departureDate: nil)
        let mins = visit.effectiveDurationMinutes(cappedAt: nil)
        let expectedMinutes = Int(Date().timeIntervalSince(arrival) / 60)
        XCTAssertGreaterThanOrEqual(mins, max(0, expectedMinutes - 1))
        XCTAssertLessThanOrEqual(mins, expectedMinutes + 1)
    }

    // MARK: - Helpers

    private func makeVisit(hour: Int) -> Visit {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 30
        let date = Calendar.current.date(from: components)!
        return Visit(arrivalDate: date, departureDate: date.addingTimeInterval(3600))
    }
}
