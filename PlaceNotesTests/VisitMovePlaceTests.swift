import XCTest
import SwiftData
@testable import PlaceNotes

final class VisitMovePlaceTests: XCTestCase {

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

    func testMovePlaceCarriesJournalEntriesToNewPlace() {
        let original = Place(name: "Cafe A", latitude: 10, longitude: 20)
        let corrected = Place(name: "Cafe B", latitude: 30, longitude: 40)
        context.insert(original)
        context.insert(corrected)
        let visit = Visit(arrivalDate: Date(), place: original)
        context.insert(visit)
        let entry = JournalEntry(photoAssetIdentifiers: ["a.jpg"])
        context.insert(entry)
        entry.place = original
        entry.visit = visit

        visit.movePlace(to: corrected)

        XCTAssertEqual(visit.place?.id, corrected.id)
        XCTAssertEqual(entry.place?.id, corrected.id)
    }

    func testMovePlaceLeavesEntriesFiledElsewhereAlone() {
        let original = Place(name: "Cafe A", latitude: 10, longitude: 20)
        let corrected = Place(name: "Cafe B", latitude: 30, longitude: 40)
        let other = Place(name: "Library", latitude: 50, longitude: 60)
        [original, corrected, other].forEach { context.insert($0) }
        let visit = Visit(arrivalDate: Date(), place: original)
        context.insert(visit)
        let entry = JournalEntry()
        context.insert(entry)
        entry.place = other
        entry.visit = visit

        visit.movePlace(to: corrected)

        XCTAssertEqual(entry.place?.id, other.id)
    }
}
