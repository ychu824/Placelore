import XCTest
import SwiftData
@testable import PlaceNotes

final class PhotoLibraryExporterTests: XCTestCase {

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

    func testItemsCarryEntryDateAndPlaceLocation() {
        let place = Place(name: "Cafe", latitude: 37.5, longitude: -122.25)
        context.insert(place)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = JournalEntry(date: date, photoAssetIdentifiers: ["a.jpg", "b.jpg"])
        context.insert(entry)
        entry.place = place

        let items = PhotoLibraryExporter.items(from: [entry])

        XCTAssertEqual(items.map(\.filename), ["a.jpg", "b.jpg"])
        XCTAssertEqual(items.map(\.creationDate), [date, date])
        XCTAssertEqual(items.first?.location?.coordinate.latitude, 37.5)
        XCTAssertEqual(items.first?.location?.coordinate.longitude, -122.25)
    }

    func testItemsWithoutPlaceHaveNoLocation() {
        let entry = JournalEntry(photoAssetIdentifiers: ["a.jpg"])
        context.insert(entry)

        let items = PhotoLibraryExporter.items(from: [entry])

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items.first?.location)
    }

    func testItemsSkipEntriesWithoutPhotosAndDropDuplicates() {
        let empty = JournalEntry(photoAssetIdentifiers: [])
        let first = JournalEntry(date: Date(timeIntervalSince1970: 100), photoAssetIdentifiers: ["a.jpg"])
        let second = JournalEntry(date: Date(timeIntervalSince1970: 200), photoAssetIdentifiers: ["a.jpg", "b.jpg"])
        [empty, first, second].forEach { context.insert($0) }

        let items = PhotoLibraryExporter.items(from: [empty, first, second])

        XCTAssertEqual(items.map(\.filename), ["a.jpg", "b.jpg"])
        XCTAssertEqual(items.first?.creationDate, Date(timeIntervalSince1970: 100))
    }

    func testItemForFilenameFallsBackToBareItem() {
        let entry = JournalEntry(date: Date(timeIntervalSince1970: 100), photoAssetIdentifiers: ["a.jpg"])
        context.insert(entry)

        XCTAssertEqual(PhotoLibraryExporter.item(for: "a.jpg", in: [entry]).creationDate, Date(timeIntervalSince1970: 100))

        let missing = PhotoLibraryExporter.item(for: "zzz.jpg", in: [entry])
        XCTAssertEqual(missing.filename, "zzz.jpg")
        XCTAssertNil(missing.creationDate)
        XCTAssertNil(missing.location)
    }
}
