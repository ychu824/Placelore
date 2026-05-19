import Foundation

struct TimeWindow: Equatable {
    var endDate: Date
    var lengthDays: Int
    var firstVisitDate: Date?

    var startDate: Date {
        let length = max(effectiveLengthDays, 0)
        return Calendar.current.date(byAdding: .day, value: -length, to: endDate) ?? endDate
    }

    /// Length actually represented on screen. Clamps to days since the user's
    /// first visit so an account that's only 3 days old doesn't show
    /// a phantom 15-day window stretching into pre-history.
    var effectiveLengthDays: Int {
        guard let firstVisit = firstVisitDate else { return 0 }
        let cal = Calendar.current
        let from = cal.startOfDay(for: firstVisit)
        let to = cal.startOfDay(for: endDate)
        let days = cal.dateComponents([.day], from: from, to: to).day ?? 0
        return min(lengthDays, max(0, days))
    }

    private static let scrubberDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var label: String {
        let cal = Calendar.current
        if cal.isDate(endDate, inSameDayAs: Date()) {
            let length = effectiveLengthDays
            return String(format: String(localized: "Last %d days"), length == 0 ? lengthDays : length)
        }
        return "\(Self.scrubberDateFormatter.string(from: startDate)) – \(Self.scrubberDateFormatter.string(from: endDate))"
    }
}
