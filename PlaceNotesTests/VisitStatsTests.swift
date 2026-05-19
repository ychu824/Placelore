import XCTest
@testable import PlaceNotes

final class VisitStatsTests: XCTestCase {

    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1
        return cal
    }

    private func date(_ iso: String, calendar: Calendar) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = calendar.timeZone
        return f.date(from: iso)!
    }

    private func visit(_ iso: String, calendar: Calendar) -> Visit {
        Visit(arrivalDate: date(iso, calendar: calendar))
    }

    func test_monthBuckets_emptyVisits_returns12ZeroBuckets() {
        let cal = utcCalendar()
        let now = date("2026-05-17T12:00:00Z", calendar: cal)
        let buckets = VisitStats.monthBuckets(for: [], endingAt: now, calendar: cal)
        XCTAssertEqual(buckets.count, 12)
        XCTAssertEqual(buckets.map(\.count), Array(repeating: 0, count: 12))
    }

    func test_monthBuckets_groupsByCalendarMonth() {
        let cal = utcCalendar()
        let now = date("2026-05-17T12:00:00Z", calendar: cal)
        let visits = [
            visit("2026-05-01T08:00:00Z", calendar: cal),
            visit("2026-05-15T08:00:00Z", calendar: cal),
            visit("2026-04-20T08:00:00Z", calendar: cal),
        ]
        let buckets = VisitStats.monthBuckets(for: visits, endingAt: now, calendar: cal)
        XCTAssertEqual(buckets.count, 12)
        XCTAssertEqual(buckets.last?.count, 2)
        XCTAssertEqual(buckets[buckets.count - 2].count, 1)
    }

    func test_monthBuckets_fixedNowAnchor_endsAtCorrectMonth() {
        let cal = utcCalendar()
        let now = date("2026-05-17T12:00:00Z", calendar: cal)
        let buckets = VisitStats.monthBuckets(for: [], endingAt: now, calendar: cal)
        let lastId = buckets.last!.id
        let comps = cal.dateComponents([.year, .month], from: lastId)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 5)
    }

    func test_monthBuckets_visitsOlderThan12MonthsAreIgnored() {
        let cal = utcCalendar()
        let now = date("2026-05-17T12:00:00Z", calendar: cal)
        let visits = [
            visit("2024-01-01T08:00:00Z", calendar: cal),
            visit("2026-05-01T08:00:00Z", calendar: cal),
        ]
        let buckets = VisitStats.monthBuckets(for: visits, endingAt: now, calendar: cal)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.count }, 1)
    }

    func test_hourBuckets_returns24ZeroFilledBuckets() {
        let cal = utcCalendar()
        let buckets = VisitStats.hourBuckets(for: [], calendar: cal)
        XCTAssertEqual(buckets.count, 24)
        XCTAssertEqual(buckets.map(\.id), Array(0..<24))
        XCTAssertEqual(buckets.map(\.count), Array(repeating: 0, count: 24))
    }

    func test_hourBuckets_visitAtMidnight_landsInBucket0() {
        let cal = utcCalendar()
        let v = visit("2026-05-15T00:30:00Z", calendar: cal)
        let buckets = VisitStats.hourBuckets(for: [v], calendar: cal)
        XCTAssertEqual(buckets[0].count, 1)
        XCTAssertEqual(buckets[1].count, 0)
    }

    func test_hourBuckets_dstSpringForward_usesLocalHour() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let comps = DateComponents(
            calendar: cal,
            timeZone: cal.timeZone,
            year: 2026, month: 3, day: 8, hour: 3, minute: 0
        )
        let arrival = cal.date(from: comps)!
        let v = Visit(arrivalDate: arrival)
        let buckets = VisitStats.hourBuckets(for: [v], calendar: cal)
        XCTAssertEqual(buckets[3].count, 1)
    }

    func test_weekdayBuckets_returns7BucketsOrderedByFirstWeekday() {
        var cal = utcCalendar()
        cal.firstWeekday = 2
        let buckets = VisitStats.weekdayBuckets(for: [], calendar: cal)
        XCTAssertEqual(buckets.count, 7)
        XCTAssertEqual(buckets.first?.id, 2)
        XCTAssertEqual(buckets.last?.id, 1)
    }

    func test_weekdayBuckets_countsByWeekday() {
        let cal = utcCalendar()
        let v = visit("2026-05-17T12:00:00Z", calendar: cal)
        let buckets = VisitStats.weekdayBuckets(for: [v], calendar: cal)
        let sunday = buckets.first { $0.id == 1 }!
        XCTAssertEqual(sunday.count, 1)
    }
}
