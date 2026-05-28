import XCTest
import SwiftData
@testable import PlaceNotes

final class HomePhotoFeedTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([JournalEntry.self, Place.self, Visit.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    func testFlattenReturnsEmptyForEmptyInput() {
        XCTAssertTrue(HomePhotoFeed.flatten([]).isEmpty)
    }

    func testFlattenSkipsEntriesWithNoPhotos() {
        let entry = JournalEntry(title: "no photos", date: Date(), photoAssetIdentifiers: [])
        context.insert(entry)
        XCTAssertTrue(HomePhotoFeed.flatten([entry]).isEmpty)
    }

    func testFlattenEmitsOneItemPerFilename() {
        let date = Date(timeIntervalSince1970: 1_000)
        let entry = JournalEntry(
            title: "two",
            date: date,
            photoAssetIdentifiers: ["a.jpg", "b.jpg"]
        )
        context.insert(entry)

        let items = HomePhotoFeed.flatten([entry])

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].filename, "a.jpg")
        XCTAssertEqual(items[1].filename, "b.jpg")
        XCTAssertEqual(items[0].date, date)
        XCTAssertEqual(items[1].date, date)
        XCTAssertEqual(items[0].entryID, entry.persistentModelID)
        XCTAssertEqual(items[1].entryID, entry.persistentModelID)
    }

    func testFlattenPreservesEntryOrder() {
        let newer = JournalEntry(date: Date(timeIntervalSince1970: 2_000),
                                 photoAssetIdentifiers: ["new.jpg"])
        let older = JournalEntry(date: Date(timeIntervalSince1970: 1_000),
                                 photoAssetIdentifiers: ["old.jpg"])
        context.insert(newer)
        context.insert(older)

        let items = HomePhotoFeed.flatten([newer, older])

        XCTAssertEqual(items.map(\.filename), ["new.jpg", "old.jpg"])
    }

    func testFlattenCarriesPlaceID() {
        let place = Place(name: "Cafe", latitude: 0, longitude: 0)
        let entry = JournalEntry(date: Date(), photoAssetIdentifiers: ["a.jpg"])
        entry.place = place
        context.insert(place)
        context.insert(entry)

        let items = HomePhotoFeed.flatten([entry])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].placeID, place.persistentModelID)
    }

    func testFlattenItemIDIsFilename() {
        let entry = JournalEntry(date: Date(), photoAssetIdentifiers: ["x.jpg"])
        context.insert(entry)

        let items = HomePhotoFeed.flatten([entry])

        XCTAssertEqual(items[0].id, "x.jpg")
    }
}
