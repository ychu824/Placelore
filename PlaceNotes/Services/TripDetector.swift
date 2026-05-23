import Foundation
import CoreLocation

struct Trip: Identifiable {
    let id: String
    let startDate: Date
    let endDate: Date
    let dayCount: Int
    let distanceFromHomeKm: Double
    let visits: [Visit]

    var uniquePlaces: [Place] {
        var seen = Set<UUID>()
        var places: [Place] = []
        for visit in visits {
            guard let place = visit.place, !seen.contains(place.id) else { continue }
            seen.insert(place.id)
            places.append(place)
        }
        return places
    }

    var noteCount: Int {
        visits.reduce(0) { $0 + $1.journalEntries.count }
    }

    var photoCount: Int {
        visits.reduce(0) { total, visit in
            total + visit.journalEntries.reduce(0) { $0 + $1.photoAssetIdentifiers.count }
        }
    }
}

/// Pure helpers for deriving travel spans from recorded visits.
enum TripDetector {
    struct HomeCentroid: Codable, Equatable {
        let latitude: Double
        let longitude: Double

        var location: CLLocation {
            CLLocation(latitude: latitude, longitude: longitude)
        }
    }

    static func homeCentroid(
        from visits: [Visit],
        now: Date = Date(),
        calendar: Calendar = .current,
        lookbackDays: Int = 60
    ) -> HomeCentroid? {
        let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: now) ?? .distantPast
        var countsByPlaceID: [UUID: (place: Place, count: Int)] = [:]

        for visit in visits {
            guard visit.arrivalDate >= cutoff,
                  visit.arrivalDate <= now,
                  isNightVisit(visit, calendar: calendar),
                  let place = visit.place else {
                continue
            }
            var bucket = countsByPlaceID[place.id] ?? (place, 0)
            bucket.count += 1
            countsByPlaceID[place.id] = bucket
        }

        guard let home = countsByPlaceID.values.max(by: { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs.place.displayName > rhs.place.displayName
        })?.place else {
            return nil
        }

        return HomeCentroid(latitude: home.latitude, longitude: home.longitude)
    }

    static func detectTrips(
        from visits: [Visit],
        homeCentroid: HomeCentroid,
        minDays: Int = 2,
        minDistanceKm: Double = 50,
        calendar: Calendar = .current
    ) -> [Trip] {
        let sortedVisits = visits
            .filter { $0.place != nil }
            .sorted { $0.arrivalDate < $1.arrivalDate }

        guard !sortedVisits.isEmpty else { return [] }

        var visitsByDay: [Date: [Visit]] = [:]
        for visit in sortedVisits {
            let day = calendar.startOfDay(for: visit.arrivalDate)
            visitsByDay[day, default: []].append(visit)
        }

        let days = visitsByDay.keys.sorted()
        var trips: [Trip] = []
        var currentRun: [Date] = []

        func finishRun() {
            guard currentRun.count >= max(1, minDays) else {
                currentRun.removeAll()
                return
            }
            let runVisits = currentRun
                .flatMap { visitsByDay[$0] ?? [] }
                .sorted { $0.arrivalDate < $1.arrivalDate }
            guard !runVisits.isEmpty else {
                currentRun.removeAll()
                return
            }
            trips.append(makeTrip(
                from: runVisits,
                dayCount: currentRun.count,
                homeCentroid: homeCentroid
            ))
            currentRun.removeAll()
        }

        for day in days {
            let dayVisits = visitsByDay[day] ?? []
            let isAwayDay = !dayVisits.isEmpty && dayVisits.allSatisfy {
                distanceFromHomeKm(for: $0, homeCentroid: homeCentroid) > minDistanceKm
            }

            guard isAwayDay else {
                finishRun()
                continue
            }

            if let previousDay = currentRun.last,
               let expectedDay = calendar.date(byAdding: .day, value: 1, to: previousDay),
               !calendar.isDate(day, inSameDayAs: expectedDay) {
                finishRun()
            }
            currentRun.append(day)
        }
        finishRun()

        return trips.sorted { $0.startDate > $1.startDate }
    }

    private static func isNightVisit(_ visit: Visit, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: visit.arrivalDate)
        return hour >= 22 || hour < 6
    }

    private static func distanceFromHomeKm(for visit: Visit, homeCentroid: HomeCentroid) -> Double {
        guard let place = visit.place else { return 0 }
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        return location.distance(from: homeCentroid.location) / 1_000
    }

    private static func makeTrip(
        from visits: [Visit],
        dayCount: Int,
        homeCentroid: HomeCentroid
    ) -> Trip {
        let startDate = visits.first?.arrivalDate ?? .distantPast
        let endDate = visits
            .map { $0.departureDate ?? $0.arrivalDate }
            .max() ?? startDate
        let distances = visits.map { distanceFromHomeKm(for: $0, homeCentroid: homeCentroid) }
        let averageDistance = distances.isEmpty ? 0 : distances.reduce(0, +) / Double(distances.count)
        let id = [
            "\(Int(startDate.timeIntervalSince1970))",
            "\(Int(endDate.timeIntervalSince1970))",
            "\(visits.count)"
        ].joined(separator: "-")

        return Trip(
            id: id,
            startDate: startDate,
            endDate: endDate,
            dayCount: dayCount,
            distanceFromHomeKm: averageDistance,
            visits: visits
        )
    }
}
