import XCTest
import CoreLocation
import SwiftData
@testable import PlaceNotes

@MainActor
final class LogbookViewModelTests: XCTestCase {

    private func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(
            for: Place.self, Visit.self, JournalEntry.self,
            configurations: config
        )
    }

    private func makePlace(in container: ModelContainer, name: String, lat: Double, lon: Double) -> Place {
        let p = Place(name: name, latitude: lat, longitude: lon)
        container.mainContext.insert(p)
        return p
    }

    @discardableResult
    private func makeVisit(arrival: Date, departure: Date?, place: Place) -> Visit {
        let v = Visit(arrivalDate: arrival, departureDate: departure, place: place)
        place.visits.append(v)
        return v
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12) -> Date {
        var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h
        return Calendar.current.date(from: c)!
    }

    private func makeSettings(home: CLLocationCoordinate2D? = nil, computedAt: Date? = nil, minStay: Int = 0) -> AppSettings {
        let s = AppSettings.shared
        s.homeLatitude = home?.latitude
        s.homeLongitude = home?.longitude
        s.homeCentroidComputedAt = computedAt
        s.tripMinDays = 2
        s.tripMinDistanceKm = 50
        s.minStayMinutes = minStay
        return s
    }

    func testRefreshWithEmptyPlacesYieldsEmptySections() {
        let vm = LogbookViewModel()
        let settings = makeSettings()
        vm.refresh(places: [], settings: settings, referenceDate: date(2026, 5, 26))
        XCTAssertTrue(vm.sections.isEmpty)
    }

    func testRefreshAssemblesTripPlusThisWeekPlusEarlierInDescendingOrder() {
        let container = makeContainer()
        let home = makePlace(in: container, name: "Home", lat: 40.7128, lon: -74.0060)
        let hotel = makePlace(in: container, name: "Hotel", lat: 47.6062, lon: -122.3321)

        _ = makeVisit(arrival: date(2026, 5, 1, 10), departure: date(2026, 5, 1, 11), place: home)
        _ = makeVisit(arrival: date(2026, 5, 10, 10), departure: date(2026, 5, 10, 18), place: hotel)
        _ = makeVisit(arrival: date(2026, 5, 11, 10), departure: date(2026, 5, 11, 18), place: hotel)
        _ = makeVisit(arrival: date(2026, 5, 25, 10), departure: date(2026, 5, 25, 11), place: home)

        let settings = makeSettings(home: home.coordinate, computedAt: date(2026, 5, 26))
        let vm = LogbookViewModel()
        vm.refresh(places: [home, hotel], settings: settings, referenceDate: date(2026, 5, 26))

        XCTAssertEqual(vm.sections.count, 3)
        if case .thisWeek = vm.sections[0] {} else { XCTFail("expected thisWeek first") }
        if case .trip = vm.sections[1] {} else { XCTFail("expected trip second") }
        if case .earlier = vm.sections[2] {} else { XCTFail("expected earlier last") }
    }

    func testRefreshSkipsHomeRecomputeWhenCacheFresh() {
        let container = makeContainer()
        let home = makePlace(in: container, name: "Home", lat: 40.7128, lon: -74.0060)
        _ = makeVisit(arrival: date(2026, 5, 25, 23), departure: date(2026, 5, 26, 6), place: home)

        let cached = CLLocationCoordinate2D(latitude: 1.0, longitude: 2.0)
        let settings = makeSettings(home: cached, computedAt: date(2026, 5, 25))

        let vm = LogbookViewModel()
        vm.refresh(places: [home], settings: settings, referenceDate: date(2026, 5, 26))

        XCTAssertEqual(settings.homeLatitude, 1.0)
        XCTAssertEqual(settings.homeLongitude, 2.0)
    }

    func testRefreshRecomputesHomeWhenCacheStale() {
        let container = makeContainer()
        let home = makePlace(in: container, name: "Home", lat: 40.7128, lon: -74.0060)
        for offset in 1...3 {
            _ = makeVisit(
                arrival: date(2026, 5, 26 - offset, 23),
                departure: date(2026, 5, 27 - offset, 6),
                place: home
            )
        }

        let stale = date(2026, 5, 1)
        let settings = makeSettings(home: CLLocationCoordinate2D(latitude: 1.0, longitude: 2.0), computedAt: stale)

        let vm = LogbookViewModel()
        vm.refresh(places: [home], settings: settings, referenceDate: date(2026, 5, 26))

        XCTAssertEqual(settings.homeLatitude!, 40.7128, accuracy: 0.001)
        XCTAssertEqual(settings.homeLongitude!, -74.0060, accuracy: 0.001)
    }

    func testRefreshRespondsToMinDistanceChange() {
        let container = makeContainer()
        let home = makePlace(in: container, name: "Home", lat: 40.7128, lon: -74.0060)
        let nearby = makePlace(in: container, name: "Newark", lat: 40.7357, lon: -74.1724)
        _ = makeVisit(arrival: date(2026, 5, 10, 10), departure: date(2026, 5, 10, 18), place: nearby)
        _ = makeVisit(arrival: date(2026, 5, 11, 10), departure: date(2026, 5, 11, 18), place: nearby)

        let settings = makeSettings(home: home.coordinate, computedAt: date(2026, 5, 26))
        let vm = LogbookViewModel()
        vm.refresh(places: [home, nearby], settings: settings, referenceDate: date(2026, 5, 26))
        XCTAssertFalse(vm.sections.contains { if case .trip = $0 { return true }; return false })

        settings.tripMinDistanceKm = 5
        vm.refresh(places: [home, nearby], settings: settings, referenceDate: date(2026, 5, 26))
        XCTAssertTrue(vm.sections.contains { if case .trip = $0 { return true }; return false })
    }
}
