import Foundation
import SwiftUI
import CoreLocation
import os

@MainActor
final class LogbookViewModel: ObservableObject {
    @Published var sections: [LogbookSection] = []

    private let logger = Logger(subsystem: "PlaceNotes", category: "trips")
    private let homeCacheMaxAgeSeconds: TimeInterval = 7 * 24 * 3600
    private let thisWeekWindowSeconds: TimeInterval = 7 * 24 * 3600

    func refresh(places: [Place], settings: AppSettings, referenceDate: Date = Date()) {
        let allVisits = places.flatMap { $0.visits }
        let minStay = settings.minStayMinutes
        let filtered = allVisits.filter {
            $0.isQuickCapture || !$0.journalEntries.isEmpty || $0.durationMinutes >= minStay
        }
        let sortedAsc = filtered.sorted { $0.arrivalDate < $1.arrivalDate }

        let home = resolveHome(settings: settings, allVisitsSortedAsc: sortedAsc, referenceDate: referenceDate)

        guard let home else {
            sections = []
            return
        }

        let result = TripDetector.partition(
            visits: sortedAsc,
            home: home,
            minDays: settings.tripMinDays,
            minDistanceKm: settings.tripMinDistanceKm
        )

        logger.info("partition produced \(result.trips.count) trips, \(result.loose.count) loose visits")

        sections = assembleSections(trips: result.trips, loose: result.loose, referenceDate: referenceDate)
    }

    private func resolveHome(
        settings: AppSettings,
        allVisitsSortedAsc: [Visit],
        referenceDate: Date
    ) -> CLLocationCoordinate2D? {
        let cacheFresh: Bool = {
            guard let computedAt = settings.homeCentroidComputedAt else { return false }
            return referenceDate.timeIntervalSince(computedAt) < homeCacheMaxAgeSeconds
        }()

        if cacheFresh, let coord = settings.homeCoordinate {
            return coord
        }

        if let computed = TripDetector.computeHomeCentroid(
            visits: allVisitsSortedAsc, referenceDate: referenceDate, lookbackDays: 60
        ) {
            settings.homeLatitude = computed.latitude
            settings.homeLongitude = computed.longitude
            settings.homeCentroidComputedAt = referenceDate
            logger.info("home centroid recomputed to (\(computed.latitude), \(computed.longitude))")
            return computed
        }

        return nil
    }

    private func assembleSections(trips: [Trip], loose: [Visit], referenceDate: Date) -> [LogbookSection] {
        let thisWeekCutoff = referenceDate.addingTimeInterval(-thisWeekWindowSeconds)
        let thisWeekVisits = loose.filter { $0.arrivalDate >= thisWeekCutoff }
            .sorted { $0.arrivalDate > $1.arrivalDate }
        let olderVisits = loose.filter { $0.arrivalDate < thisWeekCutoff }

        let cal = Calendar.current
        var monthMap: [String: (year: Int, month: Int, visits: [Visit])] = [:]
        for v in olderVisits {
            let y = cal.component(.year, from: v.arrivalDate)
            let m = cal.component(.month, from: v.arrivalDate)
            let key = "\(y)-\(m)"
            monthMap[key, default: (y, m, [])].visits.append(v)
        }

        var assembled: [LogbookSection] = []
        if !thisWeekVisits.isEmpty {
            assembled.append(.thisWeek(thisWeekVisits))
        }
        for t in trips {
            assembled.append(.trip(t))
        }
        for entry in monthMap.values {
            let sorted = entry.visits.sorted { $0.arrivalDate > $1.arrivalDate }
            assembled.append(.earlier(year: entry.year, month: entry.month, visits: sorted))
        }

        assembled.sort { $0.representativeDate > $1.representativeDate }
        return assembled
    }
}
