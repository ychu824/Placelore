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

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi
        return Calendar.current.date(from: comps)!
    }

    // MARK: - computeHomeCentroid

    func testComputeHomeCentroidReturnsNilWhenNoVisits() {
        let result = TripDetector.computeHomeCentroid(visits: [], referenceDate: date(2026, 5, 26), lookbackDays: 60)
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

        let result = TripDetector.computeHomeCentroid(visits: visits, referenceDate: date(2026, 5, 26), lookbackDays: 60)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.latitude, 40.7, accuracy: 0.0001)
        XCTAssertEqual(result!.longitude, -74.0, accuracy: 0.0001)
    }

    func testComputeHomeCentroidFallsBackToFirstVisitWhenNoOvernightData() {
        let container = makeContainer()
        let p = makePlace(in: container, name: "First", lat: 1, lon: 2)
        let visits = [makeVisit(arrival: date(2026, 5, 1, 12, 0), departure: date(2026, 5, 1, 14, 0), place: p)]
        let result = TripDetector.computeHomeCentroid(visits: visits, referenceDate: date(2026, 5, 26), lookbackDays: 60)
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

        let result = TripDetector.computeHomeCentroid(visits: visits, referenceDate: date(2026, 5, 26), lookbackDays: 60)
        XCTAssertEqual(result!.latitude, 2, accuracy: 0.0001)
    }
}
