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

    /// Partition visits into trips and loose visits.
    /// A trip is a maximal contiguous run of "far" visits (distance from home
    /// > minDistanceKm) whose calendar-day span (device TZ, inclusive) >= minDays.
    /// Visits with place == nil are skipped entirely.
    static func partition(
        visits: [Visit],
        home: CLLocationCoordinate2D,
        minDays: Int,
        minDistanceKm: Double
    ) -> (trips: [Trip], loose: [Visit]) {
        let placed = visits.filter { $0.place != nil }.sorted { $0.arrivalDate < $1.arrivalDate }
        guard !placed.isEmpty else { return ([], []) }

        let homeLoc = CLLocation(latitude: home.latitude, longitude: home.longitude)
        let minDistanceMeters = minDistanceKm * 1000

        var trips: [Trip] = []
        var loose: [Visit] = []
        var currentRun: [Visit] = []

        func flushRun() {
            guard !currentRun.isEmpty else { return }
            if let trip = promoteRunToTrip(currentRun, home: home, minDays: minDays) {
                trips.append(trip)
            } else {
                loose.append(contentsOf: currentRun)
            }
            currentRun.removeAll()
        }

        for v in placed {
            guard let p = v.place else { continue }
            let placeLoc = CLLocation(latitude: p.latitude, longitude: p.longitude)
            let isFar = placeLoc.distance(from: homeLoc) > minDistanceMeters
            if isFar {
                currentRun.append(v)
            } else {
                flushRun()
                loose.append(v)
            }
        }
        flushRun()

        return (trips, loose)
    }

    private static func promoteRunToTrip(
        _ run: [Visit],
        home: CLLocationCoordinate2D,
        minDays: Int
    ) -> Trip? {
        guard let first = run.first, let last = run.last else { return nil }
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: first.arrivalDate)
        let endRef = last.departureDate ?? last.arrivalDate
        let endDay = cal.startOfDay(for: endRef)
        let spanDays = (cal.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        guard spanDays >= minDays else { return nil }
        return buildTrip(from: run, home: home)
    }

    /// Stub — fully implemented in Task 5. Partition tests don't inspect stat fields.
    static func buildTrip(from run: [Visit], home: CLLocationCoordinate2D) -> Trip {
        let first = run.first!
        let last = run.last!
        let endDate = last.departureDate ?? last.arrivalDate
        return Trip(
            id: UUID(),
            startDate: first.arrivalDate,
            endDate: endDate,
            visits: run,
            meanDistanceFromHomeMeters: 0,
            centroidLatitude: 0,
            centroidLongitude: 0,
            uniquePlaceCount: 0,
            photoCount: 0,
            journalEntryCount: 0,
            title: ""
        )
    }
}
