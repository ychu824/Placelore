import XCTest
import SwiftData
@testable import PlaceNotes

@MainActor
final class PolaroidSelectionTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Place.self, Visit.self, JournalEntry.self, CustomCategory.self, RawLocationSample.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeEntry(in context: ModelContext, photos: [String], date: Date) -> JournalEntry {
        let entry = JournalEntry(date: date, photoAssetIdentifiers: photos)
        context.insert(entry)
        return entry
    }

    func testEmptyInputReturnsEmpty() throws {
        let ctx = try makeContext()
        XCTAssertEqual(PolaroidSelection.selectFor(entries: []).count, 0)
        _ = ctx
    }

    func testEntriesWithoutPhotosAreFilteredOut() throws {
        let ctx = try makeContext()
        let a = makeEntry(in: ctx, photos: [], date: Date())
        let b = makeEntry(in: ctx, photos: ["x.jpg"], date: Date())
        let result = PolaroidSelection.selectFor(entries: [a, b])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, b.id)
    }

    func testSelectionTakesAtMostTwo() throws {
        let ctx = try makeContext()
        let now = Date()
        let entries = (0..<5).map { i in
            makeEntry(in: ctx, photos: ["\(i).jpg"], date: now.addingTimeInterval(TimeInterval(-i * 60)))
        }
        let result = PolaroidSelection.selectFor(entries: entries)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, entries[0].id)
        XCTAssertEqual(result[1].id, entries[1].id)
    }

    func testSelectionPreservesInputOrder() throws {
        let ctx = try makeContext()
        let now = Date()
        let newer = makeEntry(in: ctx, photos: ["a.jpg"], date: now)
        let older = makeEntry(in: ctx, photos: ["b.jpg"], date: now.addingTimeInterval(-3600))
        let result = PolaroidSelection.selectFor(entries: [newer, older])
        XCTAssertEqual(result.first?.id, newer.id)
        XCTAssertEqual(result.last?.id, older.id)
    }
}
