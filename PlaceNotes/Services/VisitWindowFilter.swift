import CoreLocation
import Foundation

enum VisitWindowFilter {
    static func visits(in window: TimeWindow, from all: [Visit]) -> [Visit] {
        let start = window.startDate
        let end = window.endDate
        return all.filter { $0.arrivalDate >= start && $0.arrivalDate <= end }
    }

    /// One WeightedPoint per place at its centroid; weight = total minutes
    /// across the supplied visits. Active visits (nil departureDate) are
    /// treated as ending now.
    static func weighted(_ visits: [Visit]) -> [WeightedPoint] {
        var minutesByPlaceID: [UUID: Double] = [:]
        var coordByPlaceID: [UUID: CLLocationCoordinate2D] = [:]
        let now = Date()
        for visit in visits {
            guard let place = visit.place else { continue }
            let depart = visit.departureDate ?? now
            let minutes = depart.timeIntervalSince(visit.arrivalDate) / 60
            guard minutes > 0 else { continue }
            minutesByPlaceID[place.id, default: 0] += minutes
            coordByPlaceID[place.id] = place.coordinate
        }
        return minutesByPlaceID.compactMap { id, weight in
            guard let coord = coordByPlaceID[id] else { return nil }
            return WeightedPoint(coordinate: coord, weight: weight)
        }
    }

    static func samples(
        in window: TimeWindow,
        from all: [RawLocationSample],
        capDays: Int = 7
    ) -> [RawLocationSample] {
        let capStart = Calendar.current.date(byAdding: .day, value: -capDays, to: window.endDate) ?? window.endDate
        let effectiveStart = max(window.startDate, capStart)
        return all.filter { $0.timestamp >= effectiveStart && $0.timestamp <= window.endDate }
    }
}
