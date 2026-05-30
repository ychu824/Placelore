import XCTest
import SwiftData
@testable import PlaceNotes

@MainActor
final class DebugSeedTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Place.self, Visit.self, JournalEntry.self, CustomCategory.self,
            RawLocationSample.self, PredictionFeedback.self,
            configurations: config
        )
        return ModelContext(container)
    }

    func testClearAllDataDeletesPredictionFeedback() throws {
        let ctx = try makeContext()
        let place = Place(name: "Blue Bottle", latitude: 37.78, longitude: -122.41)
        let visit = Visit(arrivalDate: Date(), place: place)
        let feedback = PredictionFeedback(
            visitID: visit.id,
            arrivalDate: visit.arrivalDate,
            predictedPlaceName: place.name,
            predictedCategory: place.category,
            confidenceRaw: visit.confidence.rawValue,
            medianAccuracyMeters: nil,
            alternativeCount: 0,
            latitude: place.latitude,
            longitude: place.longitude,
            verdict: .accurate
        )

        ctx.insert(place)
        ctx.insert(visit)
        ctx.insert(feedback)
        try ctx.save()

        DebugSeed.clearAllData(in: ctx)

        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PredictionFeedback>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Visit>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Place>()), 0)
    }
}
