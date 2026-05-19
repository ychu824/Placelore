import XCTest
@testable import PlaceNotes

final class PlaceInsightTests: XCTestCase {

    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1
        return cal
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, calendar: Calendar) -> Date {
        let comps = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year, month: month, day: day, hour: hour
        )
        return calendar.date(from: comps)!
    }

    private func visit(year: Int, month: Int, day: Int, hour: Int, calendar: Calendar) -> Visit {
        Visit(arrivalDate: date(year: year, month: month, day: day, hour: hour, calendar: calendar))
    }

    func test_summarize_under5Visits_returnsNil() {
        let cal = utcCalendar()
        let visits = (1...4).map { day in
            visit(year: 2026, month: 5, day: day, hour: 9, calendar: cal)
        }
        let now = date(year: 2026, month: 5, day: 20, hour: 12, calendar: cal)
        XCTAssertNil(PlaceInsight.summarize(visits: visits, now: now, calendar: cal))
    }

    func test_summarize_allWeekdayMornings_returnsWeekdayMorningInsight() {
        let cal = utcCalendar()
        let weekdayDates: [(Int, Int)] = [
            (3, 2), (3, 3), (3, 4), (3, 5), (3, 6),
            (3, 9), (3, 10), (3, 11), (3, 12), (3, 16),
        ]
        let visits = weekdayDates.map { (m, d) in
            visit(year: 2026, month: m, day: d, hour: 9, calendar: cal)
        }
        let now = date(year: 2026, month: 3, day: 20, hour: 12, calendar: cal)
        let result = PlaceInsight.summarize(visits: visits, now: now, calendar: cal)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.text.lowercased().contains("weekday"))
        XCTAssertTrue(result!.text.lowercased().contains("morning"))
    }

    func test_summarize_allWeekendEvenings_returnsWeekendEveningInsight() {
        let cal = utcCalendar()
        let weekendDates: [(Int, Int)] = [
            (2, 7), (2, 8), (2, 14), (2, 15), (2, 21),
            (2, 22), (2, 28), (3, 1), (3, 7), (3, 8),
        ]
        let visits = weekendDates.map { (m, d) in
            visit(year: 2026, month: m, day: d, hour: 19, calendar: cal)
        }
        let now = date(year: 2026, month: 3, day: 20, hour: 12, calendar: cal)
        let result = PlaceInsight.summarize(visits: visits, now: now, calendar: cal)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.text.lowercased().contains("weekend"))
        XCTAssertTrue(result!.text.lowercased().contains("evening"))
    }

    func test_summarize_visitsSpanUnder14Days_skipsWeekdaySplit() {
        let cal = utcCalendar()
        let visits = (2...11).map { day in
            visit(year: 2026, month: 3, day: day, hour: 9, calendar: cal)
        }
        let now = date(year: 2026, month: 3, day: 20, hour: 12, calendar: cal)
        let result = PlaceInsight.summarize(visits: visits, now: now, calendar: cal)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.text.lowercased().contains("weekday"))
    }

    func test_summarize_evenSplit_returnsPeakHour() {
        let cal = utcCalendar()
        var visits: [Visit] = []
        let mixed: [(Int, Int)] = [
            (3, 2), (3, 3), (3, 9), (3, 10),
            (3, 7), (3, 8), (3, 14), (3, 15),
        ]
        visits += mixed.map { (m, d) in
            visit(year: 2026, month: m, day: d, hour: 15, calendar: cal)
        }
        visits.append(visit(year: 2026, month: 3, day: 16, hour: 8, calendar: cal))
        visits.append(visit(year: 2026, month: 3, day: 17, hour: 20, calendar: cal))

        let now = date(year: 2026, month: 3, day: 20, hour: 12, calendar: cal)
        let result = PlaceInsight.summarize(visits: visits, now: now, calendar: cal)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.text.lowercased().contains("3pm")
                      || result!.text.lowercased().contains("15"))
    }

    func test_summarize_peakHourBelow25Percent_skipsPeakRule() {
        let cal = utcCalendar()
        let visits: [Visit] = (0..<12).map { i in
            let day = 2 + i
            return visit(year: 2026, month: 3, day: day, hour: i + 6, calendar: cal)
        }
        let now = date(year: 2026, month: 3, day: 20, hour: 12, calendar: cal)
        XCTAssertNil(PlaceInsight.summarize(visits: visits, now: now, calendar: cal))
    }

    func test_summarize_risingTrend_returnsRising() {
        let cal = utcCalendar()
        var visits: [Visit] = [
            visit(year: 2025, month: 12, day: 1, hour: 9, calendar: cal),
            visit(year: 2026, month: 1, day: 15, hour: 14, calendar: cal),
        ]
        let recent: [(Int, Int, Int)] = [
            (3, 1, 7), (3, 8, 8), (3, 15, 11),
            (4, 2, 13), (4, 9, 16), (4, 16, 18),
            (5, 3, 20), (5, 10, 6), (5, 11, 22), (5, 17, 10),
        ]
        visits += recent.map { (m, d, h) in
            visit(year: 2026, month: m, day: d, hour: h, calendar: cal)
        }
        let now = date(year: 2026, month: 5, day: 20, hour: 12, calendar: cal)
        let result = PlaceInsight.summarize(visits: visits, now: now, calendar: cal)
        XCTAssertNotNil(result)
        let lower = result!.text.lowercased()
        XCTAssertTrue(lower.contains("more") || lower.contains("rising") || lower.contains("lately"))
    }

    func test_summarize_visitsSpanUnder4Months_skipsTrend() {
        let cal = utcCalendar()
        let visits: [Visit] = (1...12).map { day in
            visit(year: 2026, month: 5, day: day, hour: 6 + day, calendar: cal)
        }
        let now = date(year: 2026, month: 5, day: 20, hour: 12, calendar: cal)
        let result = PlaceInsight.summarize(visits: visits, now: now, calendar: cal)
        if let r = result {
            XCTAssertFalse(r.text.lowercased().contains("lately"))
            XCTAssertFalse(r.text.lowercased().contains("slowed"))
        }
    }
}
