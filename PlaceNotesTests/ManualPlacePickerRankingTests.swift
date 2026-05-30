import XCTest
import CoreLocation
@testable import PlaceNotes

@MainActor
final class ManualPlacePickerRankingTests: XCTestCase {

    private func place(_ name: String, lat: Double, lon: Double) -> Place {
        Place(name: name, latitude: lat, longitude: lon)
    }

    func testRanksByDistanceWhenCoordinateProvided() {
        let near = place("Near", lat: 37.7800, lon: -122.4100)
        let mid = place("Mid", lat: 37.7900, lon: -122.4100)
        let far = place("Far", lat: 38.0000, lon: -122.4100)
        let origin = CLLocationCoordinate2D(latitude: 37.7801, longitude: -122.4100)

        let ranked = ManualPlacePickerRanking.rank([far, mid, near], near: origin, search: "")

        XCTAssertEqual(ranked.map(\.name), ["Near", "Mid", "Far"])
    }

    func testPreservesQueryOrderWhenNoCoordinate() {
        let a = place("Alpha", lat: 0, lon: 0)
        let b = place("Bravo", lat: 0, lon: 0)
        let ranked = ManualPlacePickerRanking.rank([a, b], near: nil, search: "")
        XCTAssertEqual(ranked.map(\.name), ["Alpha", "Bravo"])
    }

    func testSearchFiltersByDisplayNameCaseInsensitively() {
        let cafe = place("Blue Bottle Cafe", lat: 0, lon: 0)
        let gym = place("Gold's Gym", lat: 0, lon: 0)
        let ranked = ManualPlacePickerRanking.rank([cafe, gym], near: nil, search: "cafe")
        XCTAssertEqual(ranked.map(\.name), ["Blue Bottle Cafe"])
    }

    func testSearchAppliesAfterDistanceOrdering() {
        let nearCafe = place("Corner Cafe", lat: 37.7800, lon: -122.4100)
        let farCafe = place("Hill Cafe", lat: 38.0000, lon: -122.4100)
        let gym = place("Gym", lat: 37.7801, lon: -122.4100)
        let origin = CLLocationCoordinate2D(latitude: 37.7801, longitude: -122.4100)

        let ranked = ManualPlacePickerRanking.rank([farCafe, gym, nearCafe], near: origin, search: "cafe")

        XCTAssertEqual(ranked.map(\.name), ["Corner Cafe", "Hill Cafe"])
    }

    func testUnsearchedResultsAreLimited() {
        let places = (0..<30).map { place("Place \($0)", lat: 0, lon: 0) }
        let ranked = ManualPlacePickerRanking.rank(places, near: nil, search: "", limit: 20)
        XCTAssertEqual(ranked.count, 20)
    }

    func testBlankSearchIsTreatedAsEmpty() {
        let a = place("Alpha", lat: 0, lon: 0)
        let ranked = ManualPlacePickerRanking.rank([a], near: nil, search: "   ")
        XCTAssertEqual(ranked.map(\.name), ["Alpha"])
    }
}
