import Foundation

enum VisitStats {

    struct MonthBucket: Identifiable, Equatable {
        let id: Date
        let label: String
        let count: Int
    }

    struct HourBucket: Identifiable, Equatable {
        let id: Int
        let count: Int
    }

    struct WeekdayBucket: Identifiable, Equatable {
        let id: Int
        let label: String
        let count: Int
    }

    static func monthBuckets(for visits: [Visit],
                             endingAt now: Date = .now,
                             calendar: Calendar = .current) -> [MonthBucket] {
        let monthStarts = lastNMonthStarts(12, endingAt: now, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM"

        let countsByMonth = Dictionary(grouping: visits) { v in
            startOfMonth(v.arrivalDate, calendar: calendar)
        }.mapValues { $0.count }

        return monthStarts.map { start in
            MonthBucket(
                id: start,
                label: formatter.string(from: start),
                count: countsByMonth[start] ?? 0
            )
        }
    }

    static func hourBuckets(for visits: [Visit],
                            calendar: Calendar = .current) -> [HourBucket] {
        var counts = Array(repeating: 0, count: 24)
        for v in visits {
            let h = calendar.component(.hour, from: v.arrivalDate)
            counts[h] += 1
        }
        return (0..<24).map { HourBucket(id: $0, count: counts[$0]) }
    }

    static func weekdayBuckets(for visits: [Visit],
                               calendar: Calendar = .current) -> [WeekdayBucket] {
        var counts = Array(repeating: 0, count: 8)
        for v in visits {
            let w = calendar.component(.weekday, from: v.arrivalDate)
            counts[w] += 1
        }
        let symbols = calendar.shortWeekdaySymbols
        let order = orderedWeekdays(firstWeekday: calendar.firstWeekday)
        return order.map { w in
            WeekdayBucket(id: w, label: symbols[w - 1], count: counts[w])
        }
    }

    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    private static func lastNMonthStarts(_ n: Int,
                                         endingAt now: Date,
                                         calendar: Calendar) -> [Date] {
        let current = startOfMonth(now, calendar: calendar)
        return (0..<n).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: current)
        }
    }

    private static func orderedWeekdays(firstWeekday: Int) -> [Int] {
        (0..<7).map { offset in ((firstWeekday - 1 + offset) % 7) + 1 }
    }
}
