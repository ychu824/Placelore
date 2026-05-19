import Foundation

enum PlaceInsight {

    struct Insight: Equatable {
        let emoji: String
        let text: String
    }

    private enum Band: String {
        case morning, afternoon, evening, lateNight

        var label: String {
            switch self {
            case .morning:   return "mornings"
            case .afternoon: return "afternoons"
            case .evening:   return "evenings"
            case .lateNight: return "late nights"
            }
        }

        var sunriseEmoji: String {
            switch self {
            case .morning:   return "🌅"
            case .afternoon: return "☀️"
            case .evening:   return "🌃"
            case .lateNight: return "🌙"
            }
        }

        static func from(hour: Int) -> Band {
            switch hour {
            case 5...11:  return .morning
            case 12...16: return .afternoon
            case 17...21: return .evening
            default:      return .lateNight
            }
        }
    }

    static func summarize(visits: [Visit],
                          now: Date = .now,
                          calendar: Calendar = .current) -> Insight? {
        guard visits.count >= 5 else { return nil }

        if let weekdayInsight = weekdaySplitInsight(visits: visits, calendar: calendar) {
            return weekdayInsight
        }
        if let hourInsight = peakHourInsight(visits: visits, calendar: calendar) {
            return hourInsight
        }
        if let trend = trendInsight(visits: visits, now: now, calendar: calendar) {
            return trend
        }
        return nil
    }

    private static func weekdaySplitInsight(visits: [Visit], calendar: Calendar) -> Insight? {
        guard spanDays(visits: visits, calendar: calendar) >= 14 else { return nil }

        let weekendCount = visits.filter { isWeekend($0.arrivalDate, calendar: calendar) }.count
        let weekdayCount = visits.count - weekendCount
        let total = Double(visits.count)
        let weekendShare = Double(weekendCount) / total
        let weekdayShare = Double(weekdayCount) / total

        let dominantIsWeekend: Bool
        if weekdayShare >= 0.70 {
            dominantIsWeekend = false
        } else if weekendShare >= 0.70 {
            dominantIsWeekend = true
        } else {
            return nil
        }

        let matching = visits.filter {
            isWeekend($0.arrivalDate, calendar: calendar) == dominantIsWeekend
        }
        let band = dominantBand(in: matching, calendar: calendar)
        let scope = dominantIsWeekend ? "weekend" : "weekday"
        return Insight(
            emoji: band.sunriseEmoji,
            text: "Mostly \(scope) \(band.label) here"
        )
    }

    private static func peakHourInsight(visits: [Visit], calendar: Calendar) -> Insight? {
        let buckets = VisitStats.hourBuckets(for: visits, calendar: calendar)
        guard let peak = buckets.max(by: { $0.count < $1.count }), peak.count > 0 else {
            return nil
        }
        let share = Double(peak.count) / Double(visits.count)
        guard share >= 0.25 else { return nil }
        return Insight(
            emoji: "⏰",
            text: "Most visits land around \(hourLabel(peak.id))"
        )
    }

    private static func trendInsight(visits: [Visit], now: Date, calendar: Calendar) -> Insight? {
        guard spanDays(visits: visits, calendar: calendar) >= 120 else { return nil }
        guard let currentMonthStart = startOfMonth(now, calendar: calendar) else { return nil }
        guard let recentStart = calendar.date(byAdding: .month, value: -3, to: currentMonthStart),
              let priorStart  = calendar.date(byAdding: .month, value: -6, to: currentMonthStart) else {
            return nil
        }

        let recent = visits.filter { $0.arrivalDate >= recentStart && $0.arrivalDate < currentMonthStart }.count
        let prior  = visits.filter { $0.arrivalDate >= priorStart  && $0.arrivalDate < recentStart      }.count

        guard prior > 0 else {
            return recent >= 3 ? Insight(emoji: "📈", text: "You've been visiting more lately") : nil
        }

        let change = Double(recent - prior) / Double(prior)
        if change >= 0.50 {
            return Insight(emoji: "📈", text: "You've been visiting more lately")
        }
        if change <= -0.50 {
            return Insight(emoji: "📉", text: "Visits have slowed recently")
        }
        return nil
    }

    private static func isWeekend(_ date: Date, calendar: Calendar) -> Bool {
        let w = calendar.component(.weekday, from: date)
        return w == 1 || w == 7
    }

    private static func dominantBand(in visits: [Visit], calendar: Calendar) -> Band {
        var counts: [Band: Int] = [:]
        for v in visits {
            let hour = calendar.component(.hour, from: v.arrivalDate)
            counts[Band.from(hour: hour), default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? .morning
    }

    private static func spanDays(visits: [Visit], calendar: Calendar) -> Int {
        guard let first = visits.map(\.arrivalDate).min(),
              let last  = visits.map(\.arrivalDate).max() else { return 0 }
        let comps = calendar.dateComponents([.day], from: first, to: last)
        return comps.day ?? 0
    }

    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date? {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps)
    }

    private static func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0:        return "midnight"
        case 12:       return "noon"
        case 1...11:   return "\(hour)am"
        default:       return "\(hour - 12)pm"
        }
    }
}
