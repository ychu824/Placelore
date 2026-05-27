import Foundation
import CoreLocation

struct Trip: Identifiable, Hashable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let visits: [Visit]
    let meanDistanceFromHomeMeters: Double
    let centroidLatitude: Double
    let centroidLongitude: Double
    let uniquePlaceCount: Int
    let photoCount: Int
    let journalEntryCount: Int
    let title: String

    var centroid: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centroidLatitude, longitude: centroidLongitude)
    }

    var dayCount: Int {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: startDate)
        let endDay = cal.startOfDay(for: endDate)
        let days = cal.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return days + 1
    }

    static func == (lhs: Trip, rhs: Trip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum LogbookSection: Identifiable {
    case trip(Trip)
    case thisWeek([Visit])
    case earlier(year: Int, month: Int, visits: [Visit])

    var id: String {
        switch self {
        case .trip(let t): return "trip-\(t.id.uuidString)"
        case .thisWeek: return "thisWeek"
        case .earlier(let y, let m, _): return "earlier-\(y)-\(m)"
        }
    }

    var representativeDate: Date {
        let cal = Calendar.current
        switch self {
        case .trip(let t):
            return t.startDate
        case .thisWeek(let visits):
            return visits.first?.arrivalDate ?? .distantPast
        case .earlier(let y, let m, _):
            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = 1
            return cal.date(from: comps) ?? .distantPast
        }
    }
}
