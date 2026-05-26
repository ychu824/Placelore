import Foundation
import CoreLocation

enum TripDetector {

    /// Compute the user's home centroid as the most-visited Place where any visit's
    /// arrivalDate hour falls in [22, 24) ∪ [0, 6) device-local, within the last
    /// `lookbackDays` days from `referenceDate`. If no such overnight data exists,
    /// fall back to the first-ever visit's place. Returns nil only when visits is empty.
    static func computeHomeCentroid(
        visits: [Visit],
        referenceDate: Date = Date(),
        lookbackDays: Int = 60,
        calendar: Calendar = .current
    ) -> CLLocationCoordinate2D? {
        guard !visits.isEmpty else { return nil }
        let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: referenceDate) ?? referenceDate

        let overnightVisits = visits.filter { v in
            guard v.place != nil else { return false }
            guard v.arrivalDate >= cutoff else { return false }
            let hour = calendar.component(.hour, from: v.arrivalDate)
            return hour >= 22 || hour < 6
        }

        if !overnightVisits.isEmpty {
            var counts: [UUID: (count: Int, place: Place)] = [:]
            for v in overnightVisits {
                guard let p = v.place else { continue }
                counts[p.id, default: (0, p)].count += 1
            }
            if let best = counts.values.max(by: { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                return lhs.place.id.uuidString > rhs.place.id.uuidString
            }) {
                return best.place.coordinate
            }
        }

        let firstEver = visits.sorted(by: { $0.arrivalDate < $1.arrivalDate }).first
        return firstEver?.place?.coordinate
    }
}
