import XCTest
@testable import PlaceNotes

final class MapAnnotationIdentityTests: XCTestCase {

    private func makeRanking(_ place: Place) -> PlaceRanking {
        PlaceRanking(place: place, qualifiedStays: 1, totalMinutes: 60)
    }

    func testSingleItemIdChangesWhenNicknameChanges() {
        let place = Place(name: "Original", latitude: 37.0, longitude: -122.0, category: "Cafe")
        let idBefore = SingleItem(ranking: makeRanking(place)).id

        place.nickname = "Renamed"
        let idAfter = SingleItem(ranking: makeRanking(place)).id

        XCTAssertNotEqual(idBefore, idAfter)
    }

    func testSingleItemIdChangesWhenEmojiChanges() {
        let place = Place(name: "Spot", latitude: 37.0, longitude: -122.0, category: "Cafe")
        let idBefore = SingleItem(ranking: makeRanking(place)).id

        place.customEmoji = "🌟"
        let idAfter = SingleItem(ranking: makeRanking(place)).id

        XCTAssertNotEqual(idBefore, idAfter)
    }

    func testSingleItemIdStableWhenNothingDisplayRelevantChanges() {
        let place = Place(name: "Spot", latitude: 37.0, longitude: -122.0, category: "Cafe")
        let id1 = SingleItem(ranking: makeRanking(place)).id
        let id2 = SingleItem(ranking: makeRanking(place)).id
        XCTAssertEqual(id1, id2)
    }

    func testSingleItemIdEncodesPlaceUUID() {
        let place = Place(name: "Spot", latitude: 0, longitude: 0)
        let id = SingleItem(ranking: makeRanking(place)).id
        XCTAssertTrue(id.contains(place.id.uuidString))
        XCTAssertTrue(id.contains(place.displayName))
    }
}
