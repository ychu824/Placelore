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
        minDistanceKm: Double,
        calendar: Calendar = .current
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
            if let trip = promoteRunToTrip(currentRun, home: home, minDays: minDays, calendar: calendar) {
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
        minDays: Int,
        calendar: Calendar
    ) -> Trip? {
        guard let first = run.first, let last = run.last else { return nil }
        let startDay = calendar.startOfDay(for: first.arrivalDate)
        let endRef = last.departureDate ?? last.arrivalDate
        let endDay = calendar.startOfDay(for: endRef)
        let spanDays = (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        guard spanDays >= minDays else { return nil }
        return buildTrip(from: run, home: home)
    }

    static func buildTrip(from run: [Visit], home: CLLocationCoordinate2D) -> Trip {
        precondition(!run.isEmpty, "buildTrip requires at least one visit")
        let first = run.first!
        let last = run.last!
        let endDate = last.departureDate ?? last.arrivalDate

        let homeLoc = CLLocation(latitude: home.latitude, longitude: home.longitude)
        var totalDistance: Double = 0
        var placeCounts: [UUID: (count: Int, place: Place)] = [:]
        var photoCount = 0
        var journalCount = 0

        for v in run {
            guard let p = v.place else { continue }
            totalDistance += CLLocation(latitude: p.latitude, longitude: p.longitude).distance(from: homeLoc)
            placeCounts[p.id, default: (0, p)].count += 1
            for entry in v.journalEntries {
                journalCount += 1
                photoCount += entry.photoAssetIdentifiers.count
            }
        }

        let validCount = run.compactMap { $0.place }.count
        let meanDistance = validCount > 0 ? totalDistance / Double(validCount) : 0

        var weightedLat: Double = 0
        var weightedLon: Double = 0
        var weightSum: Double = 0
        for (_, entry) in placeCounts {
            let w = Double(entry.count)
            weightedLat += entry.place.latitude * w
            weightedLon += entry.place.longitude * w
            weightSum += w
        }
        let centroidLat = weightSum > 0 ? weightedLat / weightSum : 0
        let centroidLon = weightSum > 0 ? weightedLon / weightSum : 0

        let topPlace = placeCounts.values.max(by: { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs.place.id.uuidString > rhs.place.id.uuidString
        })?.place
        let title: String = topPlace?.city ?? topPlace?.name ?? "Trip"

        let idSeed = "\(first.arrivalDate.timeIntervalSince1970)-\(endDate.timeIntervalSince1970)"
        let id = UUID(uuidString: stableUUID(from: idSeed)) ?? UUID()

        return Trip(
            id: id,
            startDate: first.arrivalDate,
            endDate: endDate,
            visits: run,
            meanDistanceFromHomeMeters: meanDistance,
            centroidLatitude: centroidLat,
            centroidLongitude: centroidLon,
            uniquePlaceCount: placeCounts.count,
            photoCount: photoCount,
            journalEntryCount: journalCount,
            title: title
        )
    }

    private static func stableUUID(from seed: String) -> String {
        let hash = abs(seed.hashValue)
        let bytes = withUnsafeBytes(of: hash) { Data($0) } + Data(repeating: 0, count: 16)
        let prefix = bytes.prefix(16)
        let hex = prefix.map { String(format: "%02x", $0) }.joined()
        let g1 = hex.prefix(8)
        let g2 = hex.dropFirst(8).prefix(4)
        let g3 = hex.dropFirst(12).prefix(4)
        let g4 = hex.dropFirst(16).prefix(4)
        let g5 = hex.dropFirst(20).prefix(12)
        return "\(g1)-\(g2)-\(g3)-\(g4)-\(g5)"
    }
}
