import XCTest
import SwiftData
@testable import PlaceNotes

@MainActor
final class TripDetectorTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testHomeCentroidUsesMostVisitedNightPlaceInLookbackWindow() {
        let context = try! makeContext()
        let now = date(year: 2026, month: 5, day: 20, hour: 12)
        let home = place("Home", lat: 37.7749, lon: -122.4194, in: context)
        let hotel = place("Hotel", lat: 34.0522, lon: -118.2437, in: context)
        let visits = [
            visit(home, year: 2026, month: 5, day: 15, hour: 23, in: context),
            visit(home, year: 2026, month: 5, day: 16, hour: 1, in: context),
            visit(hotel, year: 2026, month: 5, day: 17, hour: 23, in: context),
            visit(home, year: 2026, month: 2, day: 1, hour: 23, in: context)
        ]

        let centroid = TripDetector.homeCentroid(
            from: visits,
            now: now,
            calendar: calendar,
            lookbackDays: 60
        )

        XCTAssertEqual(centroid?.latitude, home.latitude)
        XCTAssertEqual(centroid?.longitude, home.longitude)
    }

    func testHomeCentroidIgnoresDaytimeVisits() {
        let context = try! makeContext()
        let now = date(year: 2026, month: 5, day: 20, hour: 12)
        let home = place("Home", lat: 37.7749, lon: -122.4194, in: context)
        let office = place("Office", lat: 37.7890, lon: -122.4010, in: context)
        let visits = [
            visit(office, year: 2026, month: 5, day: 15, hour: 10, in: context),
            visit(office, year: 2026, month: 5, day: 16, hour: 11, in: context),
            visit(home, year: 2026, month: 5, day: 17, hour: 23, in: context)
        ]

        let centroid = TripDetector.homeCentroid(
            from: visits,
            now: now,
            calendar: calendar,
            lookbackDays: 60
        )

        XCTAssertEqual(centroid?.latitude, home.latitude)
        XCTAssertEqual(centroid?.longitude, home.longitude)
    }

    func testDetectTripsGroupsConsecutiveAwayDays() {
        let context = try! makeContext()
        let home = place("Home", lat: 37.7749, lon: -122.4194, in: context)
        let cafe = place("Stumptown", lat: 45.5228, lon: -122.6819, city: "Portland", in: context)
        let dinner = place("Pok Pok", lat: 45.5049, lon: -122.6321, city: "Portland", in: context)
        let visits = [
            visit(home, year: 2026, month: 5, day: 7, hour: 22, in: context),
            visit(cafe, year: 2026, month: 5, day: 8, hour: 9, in: context),
            visit(dinner, year: 2026, month: 5, day: 9, hour: 19, in: context),
            visit(cafe, year: 2026, month: 5, day: 10, hour: 10, in: context)
        ]

        let trips = TripDetector.detectTrips(
            from: visits,
            homeCentroid: TripDetector.HomeCentroid(latitude: home.latitude, longitude: home.longitude),
            minDays: 2,
            minDistanceKm: 50,
            calendar: calendar
        )

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].dayCount, 3)
        XCTAssertEqual(trips[0].visits.map { $0.place?.displayName }, ["Stumptown", "Pok Pok", "Stumptown"])
        XCTAssertGreaterThan(trips[0].distanceFromHomeKm, 800)
    }

    func testDetectTripsBreaksWhenAnyVisitOnDayIsLocal() {
        let context = try! makeContext()
        let home = place("Home", lat: 37.7749, lon: -122.4194, in: context)
        let away = place("Away", lat: 34.0522, lon: -118.2437, in: context)
        let visits = [
            visit(away, year: 2026, month: 5, day: 8, hour: 9, in: context),
            visit(home, year: 2026, month: 5, day: 9, hour: 22, in: context),
            visit(away, year: 2026, month: 5, day: 10, hour: 9, in: context)
        ]

        let trips = TripDetector.detectTrips(
            from: visits,
            homeCentroid: TripDetector.HomeCentroid(latitude: home.latitude, longitude: home.longitude),
            minDays: 2,
            minDistanceKm: 50,
            calendar: calendar
        )

        XCTAssertTrue(trips.isEmpty)
    }

    func testDetectTripsRequiresMinimumCalendarDays() {
        let context = try! makeContext()
        let home = place("Home", lat: 37.7749, lon: -122.4194, in: context)
        let away = place("Away", lat: 34.0522, lon: -118.2437, in: context)
        let visits = [
            visit(away, year: 2026, month: 5, day: 8, hour: 9, in: context),
            visit(away, year: 2026, month: 5, day: 8, hour: 19, in: context)
        ]

        let trips = TripDetector.detectTrips(
            from: visits,
            homeCentroid: TripDetector.HomeCentroid(latitude: home.latitude, longitude: home.longitude),
            minDays: 2,
            minDistanceKm: 50,
            calendar: calendar
        )

        XCTAssertTrue(trips.isEmpty)
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Place.self, Visit.self, JournalEntry.self, CustomCategory.self, RawLocationSample.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func place(
        _ name: String,
        lat: Double,
        lon: Double,
        city: String? = nil,
        in context: ModelContext
    ) -> Place {
        let place = Place(name: name, latitude: lat, longitude: lon, city: city)
        context.insert(place)
        return place
    }

    private func visit(
        _ place: Place,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        in context: ModelContext
    ) -> Visit {
        let arrival = date(year: year, month: month, day: day, hour: hour)
        let visit = Visit(
            arrivalDate: arrival,
            departureDate: arrival.addingTimeInterval(60 * 60),
            place: place
        )
        context.insert(visit)
        return visit
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
