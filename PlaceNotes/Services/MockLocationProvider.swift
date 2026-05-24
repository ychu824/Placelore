import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "dev.placelore.app", category: "MockLocationProvider")

/// Provides simulated location visits for debug builds and
/// cleans up mock data when switching to release.
final class MockLocationProvider {

    private static let seededKey = "mockDataSeeded_debug"
    /// Bump this version to force a re-seed (e.g. after adding new mock fields).
    private static let seedVersion = 4
    private static let seedVersionKey = "mockDataSeedVersion"

    /// Whether mock data has been seeded into the current debug database.
    static var hasSeededData: Bool {
        UserDefaults.standard.bool(forKey: seededKey)
    }

    /// Whether the seeded data is up-to-date with the current seed version.
    static var isCurrentVersion: Bool {
        UserDefaults.standard.integer(forKey: seedVersionKey) >= seedVersion
    }

    struct MockPlace {
        let name: String
        let latitude: Double
        let longitude: Double
        let category: String
        let city: String
        let state: String
    }

    static let samplePlaces: [MockPlace] = [
        MockPlace(name: "Blue Bottle Coffee", latitude: 37.7830, longitude: -122.4090, category: "Cafe", city: "San Francisco", state: "CA"),
        MockPlace(name: "Whole Foods Market", latitude: 37.7850, longitude: -122.4070, category: "Grocery", city: "San Francisco", state: "CA"),
        MockPlace(name: "Barry's Bootcamp", latitude: 37.7870, longitude: -122.4050, category: "Gym", city: "San Francisco", state: "CA"),
        MockPlace(name: "Nobu Restaurant", latitude: 37.7860, longitude: -122.3900, category: "Restaurant", city: "San Francisco", state: "CA"),
        MockPlace(name: "San Francisco Library", latitude: 37.7790, longitude: -122.4160, category: "Library", city: "San Francisco", state: "CA"),
        MockPlace(name: "Chase Bank", latitude: 37.7900, longitude: -122.4000, category: "Bank", city: "San Francisco", state: "CA"),
        MockPlace(name: "Golden Gate Park", latitude: 37.7694, longitude: -122.4862, category: "Park", city: "San Francisco", state: "CA"),
        MockPlace(name: "UCSF Medical Center", latitude: 37.7631, longitude: -122.4580, category: "Hospital", city: "San Francisco", state: "CA"),
    ]

    /// Seeds the database with sample places and visits spread over the past 30 days.
    /// Only runs once per install and only in DEBUG builds.
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        // Re-seed if version changed (e.g. new mock fields added)
        if hasSeededData && !isCurrentVersion {
            purgeIfNeeded(context: context)
        }

        guard !hasSeededData else { return }

        let descriptor = FetchDescriptor<Place>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        let calendar = Calendar.current
        let now = Date()
        let tripDayOffsets: Set<Int> = [7, 8, 9, 24, 25, 26, 27]

        for mockPlace in samplePlaces {
            let place = Place(
                name: mockPlace.name,
                latitude: mockPlace.latitude,
                longitude: mockPlace.longitude,
                category: mockPlace.category,
                city: mockPlace.city,
                state: mockPlace.state
            )
            context.insert(place)

            // Generate random visits over the past 90 days (spans multiple months)
            let visitCount = Int.random(in: 5...20)
            for _ in 0..<visitCount {
                let daysAgo = Int.random(in: 0...89)
                guard !tripDayOffsets.contains(daysAgo) else { continue }
                let hour = Int.random(in: 6...22)
                let minute = Int.random(in: 0...59)
                let durationMinutes = Int.random(in: 5...180)

                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.day = (components.day ?? 0) - daysAgo
                components.hour = hour
                components.minute = minute

                guard let arrival = calendar.date(from: components) else { continue }
                let departure = arrival.addingTimeInterval(Double(durationMinutes) * 60)

                let visit = Visit(arrivalDate: arrival, departureDate: departure, place: place)

                // Assign a random confidence level for testing
                let confidences: [PlaceConfidence] = [.high, .high, .high, .medium, .medium, .low]
                visit.confidence = confidences.randomElement() ?? .high
                visit.medianAccuracyMeters = Double.random(in: 5...60)

                // Give ~half the visits some alternative place candidates so
                // the "Wrong Place?" feature can be tested in debug builds.
                if Bool.random() {
                    let others = samplePlaces.filter { $0.name != mockPlace.name }.shuffled()
                    visit.alternativePlaces = Array(others.prefix(2)).map { alt in
                        PlaceCandidate(
                            name: alt.name,
                            latitude: alt.latitude,
                            longitude: alt.longitude,
                            category: alt.category,
                            city: alt.city,
                            state: alt.state,
                            distanceMeters: Double.random(in: 30...200)
                        )
                    }
                }

                context.insert(visit)
            }
        }

        seedDetectedTrips(now: now, calendar: calendar, context: context)

        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
        UserDefaults.standard.set(seedVersion, forKey: seedVersionKey)
        logger.info("Seeded debug mock places with sample visits and trips (v\(seedVersion))")
    }

    @MainActor
    private static func seedDetectedTrips(now: Date, calendar: Calendar, context: ModelContext) {
        let home = Place(
            name: "Home",
            latitude: 37.7649,
            longitude: -122.4194,
            category: "Home",
            city: "San Francisco",
            state: "CA"
        )
        let stumptown = Place(
            name: "Stumptown Coffee Roasters",
            latitude: 45.5228,
            longitude: -122.6819,
            category: "Cafe",
            city: "Portland",
            state: "OR"
        )
        let powells = Place(
            name: "Powell's City of Books",
            latitude: 45.5231,
            longitude: -122.6813,
            category: "Bookstore",
            city: "Portland",
            state: "OR"
        )
        let pokPok = Place(
            name: "Pok Pok",
            latitude: 45.5049,
            longitude: -122.6321,
            category: "Restaurant",
            city: "Portland",
            state: "OR"
        )
        let hotel = Place(
            name: "The State Hotel",
            latitude: 47.6097,
            longitude: -122.3405,
            category: "Hotel",
            city: "Seattle",
            state: "WA"
        )
        let pikePlace = Place(
            name: "Pike Place Market",
            latitude: 47.6094,
            longitude: -122.3417,
            category: "Market",
            city: "Seattle",
            state: "WA"
        )
        let museum = Place(
            name: "Seattle Art Museum",
            latitude: 47.6073,
            longitude: -122.3381,
            category: "Museum",
            city: "Seattle",
            state: "WA"
        )

        for place in [home, stumptown, powells, pokPok, hotel, pikePlace, museum] {
            context.insert(place)
        }

        // Enough recent overnight home visits to make the inferred home centroid deterministic.
        for offset in [1, 2, 3, 4, 5, 10, 12, 14, 18, 21, 30, 45] {
            addVisit(
                place: home,
                dayOffset: offset,
                startHour: 23,
                startMinute: 0,
                durationMinutes: 7 * 60,
                noteTitle: nil,
                photoCount: 0,
                now: now,
                calendar: calendar,
                context: context
            )
        }

        // Portland: 3 contiguous away days, all >50 km from home.
        addVisit(place: stumptown, dayOffset: 9, startHour: 9, startMinute: 15, durationMinutes: 45, noteTitle: "Morning coffee", photoCount: 1, now: now, calendar: calendar, context: context)
        addVisit(place: powells, dayOffset: 9, startHour: 11, startMinute: 0, durationMinutes: 100, noteTitle: "Lost in the stacks", photoCount: 2, now: now, calendar: calendar, context: context)
        addVisit(place: pokPok, dayOffset: 8, startHour: 18, startMinute: 30, durationMinutes: 95, noteTitle: "Dinner with wings", photoCount: 1, now: now, calendar: calendar, context: context)
        addVisit(place: stumptown, dayOffset: 7, startHour: 10, startMinute: 20, durationMinutes: 35, noteTitle: nil, photoCount: 0, now: now, calendar: calendar, context: context)

        // Seattle: 4 contiguous away days, useful for checking multiple trip cards.
        addVisit(place: hotel, dayOffset: 27, startHour: 22, startMinute: 10, durationMinutes: 9 * 60, noteTitle: "Checked in late", photoCount: 1, now: now, calendar: calendar, context: context)
        addVisit(place: pikePlace, dayOffset: 26, startHour: 9, startMinute: 45, durationMinutes: 120, noteTitle: "Market morning", photoCount: 2, now: now, calendar: calendar, context: context)
        addVisit(place: museum, dayOffset: 25, startHour: 13, startMinute: 0, durationMinutes: 150, noteTitle: "Afternoon galleries", photoCount: 1, now: now, calendar: calendar, context: context)
        addVisit(place: pikePlace, dayOffset: 24, startHour: 8, startMinute: 30, durationMinutes: 75, noteTitle: nil, photoCount: 0, now: now, calendar: calendar, context: context)
    }

    @MainActor
    private static func addVisit(
        place: Place,
        dayOffset: Int,
        startHour: Int,
        startMinute: Int,
        durationMinutes: Int,
        noteTitle: String?,
        photoCount: Int,
        now: Date,
        calendar: Calendar,
        context: ModelContext
    ) {
        let day = calendar.date(byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: now)) ?? now
        guard let arrival = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day) else {
            return
        }
        let visit = Visit(
            arrivalDate: arrival,
            departureDate: arrival.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            place: place
        )
        visit.confidence = .high
        visit.medianAccuracyMeters = 12
        context.insert(visit)

        guard noteTitle != nil || photoCount > 0 else { return }
        let photoIDs = (0..<photoCount).map { "debug-trip-\(visit.id.uuidString)-\($0)" }
        let entry = JournalEntry(
            title: noteTitle ?? "",
            body: noteTitle.map { "Mock trip note: \($0)." } ?? "",
            date: arrival.addingTimeInterval(10 * 60),
            photoAssetIdentifiers: photoIDs
        )
        entry.place = place
        entry.visit = visit
        context.insert(entry)
    }

    /// Known mock place names used to detect legacy seeded data
    /// that was inserted before the `mockDataSeeded` flag existed.
    private static let mockTripPlaceNames: Set<String> = [
        "Home",
        "Stumptown Coffee Roasters",
        "Powell's City of Books",
        "Pok Pok",
        "The State Hotel",
        "Pike Place Market",
        "Seattle Art Museum"
    ]

    private static let mockPlaceNames: Set<String> = Set(samplePlaces.map(\.name)).union(mockTripPlaceNames)

    /// Removes all mock-seeded data from the database.
    /// Call this in release builds to clean up leftover debug data.
    /// Detects mock data both by the UserDefaults flag AND by matching
    /// against known mock place names (handles data seeded before the flag existed).
    @MainActor
    static func purgeIfNeeded(context: ModelContext) {
        let placeDescriptor = FetchDescriptor<Place>()
        guard let places = try? context.fetch(placeDescriptor) else { return }

        let hasMockPlaces = places.contains { mockPlaceNames.contains($0.name) }
        guard hasSeededData || hasMockPlaces else { return }

        // Only delete places that match known mock names and their visits
        for place in places where mockPlaceNames.contains(place.name) {
            for visit in place.visits {
                context.delete(visit)
            }
            context.delete(place)
        }

        try? context.save()
        UserDefaults.standard.set(false, forKey: seededKey)
        logger.info("Purged mock data for release build")
    }
}
