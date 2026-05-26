import XCTest
import CoreLocation
import SwiftData
@testable import PlaceNotes

@MainActor
final class TripDetectorTests: XCTestCase {

    // MARK: - In-memory ModelContainer

    private func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(
            for: Place.self, Visit.self, JournalEntry.self,
            configurations: config
        )
    }

    private func makePlace(in container: ModelContainer, name: String, lat: Double, lon: Double, city: String? = nil) -> Place {
        let p = Place(name: name, latitude: lat, longitude: lon, city: city)
        container.mainContext.insert(p)
        return p
    }

    private func makeVisit(arrival: Date, departure: Date?, place: Place) -> Visit {
        let v = Visit(arrivalDate: arrival, departureDate: departure, place: place)
        place.visits.append(v)
        return v
    }

    private let testCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi
        return testCalendar.date(from: comps)!
    }

    // MARK: - computeHomeCentroid

    func testComputeHomeCentroidReturnsNilWhenNoVisits() {
        let result = TripDetector.computeHomeCentroid(visits: [], referenceDate: date(2026, 5, 26), lookbackDays: 60, calendar: testCalendar)
        XCTAssertNil(result)
    }

    func testComputeHomeCentroidPicksMostVisitedOvernightPlace() {
        let container = makeContainer()
        let home = makePlace(in: container, name: "Home", lat: 40.7, lon: -74.0)
        let cafe = makePlace(in: container, name: "Cafe", lat: 40.71, lon: -74.01)

        var visits: [Visit] = []
        // 3 overnight stays at home
        for offset in [1, 2, 3] {
            visits.append(makeVisit(
                arrival: date(2026, 5, 26 - offset, 23, 0),
                departure: date(2026, 5, 27 - offset, 7, 0),
                place: home
            ))
        }
        // 1 overnight at cafe
        visits.append(makeVisit(
            arrival: date(2026, 5, 20, 23, 30),
            departure: date(2026, 5, 21, 1, 0),
            place: cafe
        ))

        let result = TripDetector.computeHomeCentroid(visits: visits, referenceDate: date(2026, 5, 26), lookbackDays: 60, calendar: testCalendar)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.latitude, 40.7, accuracy: 0.0001)
        XCTAssertEqual(result!.longitude, -74.0, accuracy: 0.0001)
    }

    func testComputeHomeCentroidFallsBackToFirstVisitWhenNoOvernightData() {
        let container = makeContainer()
        let p = makePlace(in: container, name: "First", lat: 1, lon: 2)
        let visits = [makeVisit(arrival: date(2026, 5, 1, 12, 0), departure: date(2026, 5, 1, 14, 0), place: p)]
        let result = TripDetector.computeHomeCentroid(visits: visits, referenceDate: date(2026, 5, 26), lookbackDays: 60, calendar: testCalendar)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.latitude, 1, accuracy: 0.0001)
        XCTAssertEqual(result!.longitude, 2, accuracy: 0.0001)
    }

    func testComputeHomeCentroidIgnoresVisitsOutsideLookback() {
        let container = makeContainer()
        let oldHome = makePlace(in: container, name: "Old", lat: 1, lon: 1)
        let newHome = makePlace(in: container, name: "New", lat: 2, lon: 2)
        var visits: [Visit] = []
        // Old overnights, ~200 days ago (outside 60-day lookback)
        for _ in 0..<10 {
            visits.append(makeVisit(
                arrival: date(2025, 11, 1, 23, 0),
                departure: date(2025, 11, 2, 6, 0),
                place: oldHome
            ))
        }
        // Single recent overnight
        visits.append(makeVisit(
            arrival: date(2026, 5, 25, 23, 0),
            departure: date(2026, 5, 26, 6, 0),
            place: newHome
        ))

        let result = TripDetector.computeHomeCentroid(visits: visits, referenceDate: date(2026, 5, 26), lookbackDays: 60, calendar: testCalendar)
        XCTAssertEqual(result!.latitude, 2, accuracy: 0.0001)
    }

    // MARK: - partition

    private func nyc(in container: ModelContainer) -> Place {
        makePlace(in: container, name: "NYC Home", lat: 40.7128, lon: -74.0060, city: "New York")
    }

    private func sea(in container: ModelContainer) -> Place {
        makePlace(in: container, name: "SEA Hotel", lat: 47.6062, lon: -122.3321, city: "Seattle")
    }

    func testPartitionEmptyVisits() {
        let result = TripDetector.partition(
            visits: [],
            home: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            minDays: 2,
            minDistanceKm: 50,
            calendar: testCalendar
        )
        XCTAssertTrue(result.trips.isEmpty)
        XCTAssertTrue(result.loose.isEmpty)
    }

    func testPartitionAllLocalVisitsProducesNoTrips() {
        let container = makeContainer()
        let home = nyc(in: container)
        let visits = [
            makeVisit(arrival: date(2026, 5, 20, 9), departure: date(2026, 5, 20, 11), place: home),
            makeVisit(arrival: date(2026, 5, 21, 9), departure: date(2026, 5, 21, 11), place: home)
        ]
        let result = TripDetector.partition(
            visits: visits,
            home: home.coordinate,
            minDays: 2,
            minDistanceKm: 50,
            calendar: testCalendar
        )
        XCTAssertTrue(result.trips.isEmpty)
        XCTAssertEqual(result.loose.count, 2)
    }

    func testPartitionSingleFarVisitFailsMinDays() {
        let container = makeContainer()
        let home = nyc(in: container)
        let hotel = sea(in: container)
        let visits = [
            makeVisit(arrival: date(2026, 5, 20, 10), departure: date(2026, 5, 20, 14), place: hotel)
        ]
        let result = TripDetector.partition(
            visits: visits,
            home: home.coordinate,
            minDays: 2,
            minDistanceKm: 50,
            calendar: testCalendar
        )
        XCTAssertTrue(result.trips.isEmpty)
        XCTAssertEqual(result.loose.count, 1)
    }

    func testPartitionMultiDayFarRunBecomesTrip() {
        let container = makeContainer()
        let home = nyc(in: container)
        let hotel = sea(in: container)
        let visits = [
            makeVisit(arrival: date(2026, 5, 20, 14), departure: date(2026, 5, 20, 18), place: hotel),
            makeVisit(arrival: date(2026, 5, 21, 9), departure: date(2026, 5, 21, 17), place: hotel),
            makeVisit(arrival: date(2026, 5, 22, 8), departure: date(2026, 5, 22, 12), place: hotel)
        ]
        let result = TripDetector.partition(
            visits: visits,
            home: home.coordinate,
            minDays: 2,
            minDistanceKm: 50,
            calendar: testCalendar
        )
        XCTAssertEqual(result.trips.count, 1)
        XCTAssertEqual(result.loose.count, 0)
        XCTAssertEqual(result.trips[0].visits.count, 3)
    }

    func testPartitionMixedDayBoundariesPreservesLocalVisits() {
        // 5/29 NYC morning, 5/29 PM SEA flight, 5/30..6/2 SEA, 6/3 SEA AM, 6/3 PM NYC return
        let container = makeContainer()
        let home = nyc(in: container)
        let hotel = sea(in: container)
        let visits = [
            makeVisit(arrival: date(2026, 5, 29, 9),  departure: date(2026, 5, 29, 11), place: home),
            makeVisit(arrival: date(2026, 5, 29, 18), departure: date(2026, 5, 29, 22), place: hotel),
            makeVisit(arrival: date(2026, 5, 30, 10), departure: date(2026, 5, 30, 17), place: hotel),
            makeVisit(arrival: date(2026, 5, 31, 10), departure: date(2026, 5, 31, 17), place: hotel),
            makeVisit(arrival: date(2026, 6, 1, 10),  departure: date(2026, 6, 1, 17),  place: hotel),
            makeVisit(arrival: date(2026, 6, 2, 10),  departure: date(2026, 6, 2, 17),  place: hotel),
            makeVisit(arrival: date(2026, 6, 3, 9),   departure: date(2026, 6, 3, 12),  place: hotel),
            makeVisit(arrival: date(2026, 6, 3, 20),  departure: date(2026, 6, 3, 22),  place: home)
        ]
        let result = TripDetector.partition(
            visits: visits,
            home: home.coordinate,
            minDays: 2,
            minDistanceKm: 50,
            calendar: testCalendar
        )
        XCTAssertEqual(result.trips.count, 1)
        XCTAssertEqual(result.trips[0].visits.count, 6)
        XCTAssertEqual(result.loose.count, 2)
        XCTAssertTrue(result.loose.allSatisfy { $0.place?.name == "NYC Home" })
    }

    func testPartitionTwoFarRunsSplitByLocalVisit() {
        let container = makeContainer()
        let home = nyc(in: container)
        let hotel = sea(in: container)
        let visits = [
            makeVisit(arrival: date(2026, 5, 1, 10), departure: date(2026, 5, 1, 18), place: hotel),
            makeVisit(arrival: date(2026, 5, 2, 10), departure: date(2026, 5, 2, 18), place: hotel),
            makeVisit(arrival: date(2026, 5, 3, 10), departure: date(2026, 5, 3, 18), place: home),
            makeVisit(arrival: date(2026, 5, 4, 10), departure: date(2026, 5, 4, 18), place: hotel),
            makeVisit(arrival: date(2026, 5, 5, 10), departure: date(2026, 5, 5, 18), place: hotel)
        ]
        let result = TripDetector.partition(
            visits: visits,
            home: home.coordinate,
            minDays: 2,
            minDistanceKm: 50,
            calendar: testCalendar
        )
        XCTAssertEqual(result.trips.count, 2)
        XCTAssertEqual(result.loose.count, 1)
    }

    func testPartitionOpenVisitInFarRunIncluded() {
        let container = makeContainer()
        let home = nyc(in: container)
        let hotel = sea(in: container)
        let visits = [
            makeVisit(arrival: date(2026, 5, 1, 10), departure: date(2026, 5, 1, 18), place: hotel),
            makeVisit(arrival: date(2026, 5, 2, 10), departure: nil, place: hotel)
        ]
        let result = TripDetector.partition(
            visits: visits,
            home: home.coordinate,
            minDays: 2,
            minDistanceKm: 50,
            calendar: testCalendar
        )
        XCTAssertEqual(result.trips.count, 1)
        XCTAssertEqual(result.trips[0].endDate, date(2026, 5, 2, 10))
    }

    func testPartitionRespectsCustomMinDistanceKm() {
        let container = makeContainer()
        let home = nyc(in: container)
        // ~10 km away from NYC
        let nearby = makePlace(in: container, name: "Newark", lat: 40.7357, lon: -74.1724)
        let visits = [
            makeVisit(arrival: date(2026, 5, 1, 10), departure: date(2026, 5, 1, 18), place: nearby),
            makeVisit(arrival: date(2026, 5, 2, 10), departure: date(2026, 5, 2, 18), place: nearby)
        ]
        let defaultResult = TripDetector.partition(
            visits: visits, home: home.coordinate, minDays: 2, minDistanceKm: 50, calendar: testCalendar
        )
        XCTAssertTrue(defaultResult.trips.isEmpty)
        let loweredResult = TripDetector.partition(
            visits: visits, home: home.coordinate, minDays: 2, minDistanceKm: 5, calendar: testCalendar
        )
        XCTAssertEqual(loweredResult.trips.count, 1)
    }

    func testPartitionVisitWithNilPlaceIsSkipped() {
        let container = makeContainer()
        let home = nyc(in: container)
        let hotel = sea(in: container)
        let orphan = Visit(arrivalDate: date(2026, 5, 1, 10), departureDate: date(2026, 5, 1, 12), place: nil)
        let visits = [
            orphan,
            makeVisit(arrival: date(2026, 5, 2, 10), departure: date(2026, 5, 2, 18), place: hotel),
            makeVisit(arrival: date(2026, 5, 3, 10), departure: date(2026, 5, 3, 18), place: hotel)
        ]
        let result = TripDetector.partition(
            visits: visits, home: home.coordinate, minDays: 2, minDistanceKm: 50, calendar: testCalendar
        )
        XCTAssertEqual(result.trips.count, 1)
        XCTAssertFalse(result.loose.contains(where: { $0 === orphan }))
    }

    // MARK: - buildTrip

    func testBuildTripComputesMeanDistance() {
        let container = makeContainer()
        let home = nyc(in: container)
        let hotel = sea(in: container)
        let run = [
            makeVisit(arrival: date(2026, 5, 1, 10), departure: date(2026, 5, 1, 18), place: hotel),
            makeVisit(arrival: date(2026, 5, 2, 10), departure: date(2026, 5, 2, 18), place: hotel)
        ]
        let trip = TripDetector.buildTrip(from: run, home: home.coordinate)
        let expected = CLLocation(latitude: hotel.latitude, longitude: hotel.longitude)
            .distance(from: CLLocation(latitude: home.latitude, longitude: home.longitude))
        XCTAssertEqual(trip.meanDistanceFromHomeMeters, expected, accuracy: 1.0)
    }

    func testBuildTripCentroidWeightedByVisitCount() {
        let container = makeContainer()
        let home = nyc(in: container)
        let a = makePlace(in: container, name: "A", lat: 47.0, lon: -122.0)
        let b = makePlace(in: container, name: "B", lat: 48.0, lon: -123.0)
        let run = [
            makeVisit(arrival: date(2026, 5, 1, 10), departure: date(2026, 5, 1, 11), place: a),
            makeVisit(arrival: date(2026, 5, 1, 12), departure: date(2026, 5, 1, 13), place: a),
            makeVisit(arrival: date(2026, 5, 1, 14), departure: date(2026, 5, 1, 15), place: a),
            makeVisit(arrival: date(2026, 5, 2, 10), departure: date(2026, 5, 2, 11), place: b)
        ]
        let trip = TripDetector.buildTrip(from: run, home: home.coordinate)
        // Weighted: lat (47*3 + 48*1)/4 = 47.25; lon (-122*3 + -123*1)/4 = -122.25
        XCTAssertEqual(trip.centroidLatitude, 47.25, accuracy: 0.001)
        XCTAssertEqual(trip.centroidLongitude, -122.25, accuracy: 0.001)
    }

    func testBuildTripCountsPhotosAcrossVisitJournalEntries() {
        let container = makeContainer()
        let home = nyc(in: container)
        let hotel = sea(in: container)
        let v1 = makeVisit(arrival: date(2026, 5, 1, 10), departure: date(2026, 5, 1, 18), place: hotel)
        let v2 = makeVisit(arrival: date(2026, 5, 2, 10), departure: date(2026, 5, 2, 18), place: hotel)
        let entry1 = JournalEntry(title: "Day 1", body: "", date: date(2026, 5, 1, 12), photoAssetIdentifiers: ["a", "b"])
        let entry2 = JournalEntry(title: "Day 2", body: "", date: date(2026, 5, 2, 12), photoAssetIdentifiers: ["c"])
        v1.journalEntries.append(entry1)
        v2.journalEntries.append(entry2)
        let trip = TripDetector.buildTrip(from: [v1, v2], home: home.coordinate)
        XCTAssertEqual(trip.photoCount, 3)
        XCTAssertEqual(trip.journalEntryCount, 2)
    }

    func testBuildTripUniquePlaceCount() {
        let container = makeContainer()
        let home = nyc(in: container)
        let a = makePlace(in: container, name: "A", lat: 47.0, lon: -122.0)
        let b = makePlace(in: container, name: "B", lat: 48.0, lon: -123.0)
        let run = [
            makeVisit(arrival: date(2026, 5, 1, 10), departure: date(2026, 5, 1, 18), place: a),
            makeVisit(arrival: date(2026, 5, 1, 19), departure: date(2026, 5, 1, 21), place: a),
            makeVisit(arrival: date(2026, 5, 2, 10), departure: date(2026, 5, 2, 18), place: b)
        ]
        let trip = TripDetector.buildTrip(from: run, home: home.coordinate)
        XCTAssertEqual(trip.uniquePlaceCount, 2)
    }

    func testBuildTripTitleUsesMostVisitedCity() {
        let container = makeContainer()
        let home = nyc(in: container)
        let pike = makePlace(in: container, name: "Pike Place", lat: 47.6, lon: -122.3, city: "Seattle")
        let space = makePlace(in: container, name: "Space Needle", lat: 47.62, lon: -122.35, city: "Seattle")
        let run = [
            makeVisit(arrival: date(2026, 5, 1, 10), departure: date(2026, 5, 1, 12), place: pike),
            makeVisit(arrival: date(2026, 5, 1, 13), departure: date(2026, 5, 1, 15), place: space),
            makeVisit(arrival: date(2026, 5, 2, 10), departure: date(2026, 5, 2, 12), place: pike)
        ]
        let trip = TripDetector.buildTrip(from: run, home: home.coordinate)
        XCTAssertEqual(trip.title, "Seattle")
    }

    func testBuildTripTitleFallsBackToPlaceNameWhenNoCity() {
        let container = makeContainer()
        let home = nyc(in: container)
        let cabin = makePlace(in: container, name: "Cabin", lat: 47.0, lon: -122.0, city: nil)
        let run = [
            makeVisit(arrival: date(2026, 5, 1, 10), departure: date(2026, 5, 1, 18), place: cabin),
            makeVisit(arrival: date(2026, 5, 2, 10), departure: date(2026, 5, 2, 18), place: cabin)
        ]
        let trip = TripDetector.buildTrip(from: run, home: home.coordinate)
        XCTAssertEqual(trip.title, "Cabin")
    }
}
