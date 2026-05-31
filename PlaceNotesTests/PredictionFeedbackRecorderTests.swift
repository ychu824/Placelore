import XCTest
import SwiftData
@testable import PlaceNotes

@MainActor
final class PredictionFeedbackRecorderTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Place.self, Visit.self, JournalEntry.self, CustomCategory.self,
            RawLocationSample.self, PredictionFeedback.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeVisit(in ctx: ModelContext) -> Visit {
        let place = Place(name: "Blue Bottle", latitude: 37.78, longitude: -122.41, category: "Cafe")
        ctx.insert(place)
        let visit = Visit(arrivalDate: Date(), place: place)
        visit.confidence = .high
        visit.medianAccuracyMeters = 14
        visit.alternativePlaces = [
            PlaceCandidate(name: "Philz", latitude: 37.7801, longitude: -122.4101,
                           category: "Cafe", city: nil, state: nil, distanceMeters: 20)
        ]
        ctx.insert(visit)
        try? ctx.save()
        return visit
    }

    private func allFeedback(_ ctx: ModelContext) -> [PredictionFeedback] {
        (try? ctx.fetch(FetchDescriptor<PredictionFeedback>())) ?? []
    }

    func testAccurateCreatesRecordAndSetsVerdict() throws {
        let ctx = try makeContext()
        let visit = makeVisit(in: ctx)

        PredictionFeedbackRecorder.record(.accurate, for: visit, in: ctx)

        let records = allFeedback(ctx)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.verdict, .accurate)
        XCTAssertEqual(records.first?.predictedPlaceName, "Blue Bottle")
        XCTAssertEqual(records.first?.alternativeCount, 1)
        XCTAssertTrue(visit.placeConfirmed)
    }

    func testResubmittingReplacesPreviousRecord() throws {
        let ctx = try makeContext()
        let visit = makeVisit(in: ctx)

        PredictionFeedbackRecorder.record(.accurate, for: visit, in: ctx)
        PredictionFeedbackRecorder.record(.wrong, for: visit, in: ctx)

        let records = allFeedback(ctx)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.verdict, .wrong)
        XCTAssertFalse(visit.placeConfirmed)
    }

    func testWrongDoesNotConfirmPlace() throws {
        let ctx = try makeContext()
        let visit = makeVisit(in: ctx)

        PredictionFeedbackRecorder.record(.wrong, for: visit, in: ctx)

        XCTAssertFalse(visit.placeConfirmed)
        XCTAssertEqual(allFeedback(ctx).first?.verdict, .wrong)
    }

    func testCorrectedCapturesPredictionSnapshotAndCorrection() throws {
        let ctx = try makeContext()
        let visit = makeVisit(in: ctx)

        PredictionFeedbackRecorder.record(
            .corrected,
            for: visit,
            correctedName: "Philz",
            correctedCategory: "Cafe",
            correctionSource: "alternative",
            in: ctx
        )

        let record = allFeedback(ctx).first
        XCTAssertEqual(record?.verdict, .corrected)
        XCTAssertEqual(record?.predictedPlaceName, "Blue Bottle") // the wrong prediction
        XCTAssertEqual(record?.correctedPlaceName, "Philz")
        XCTAssertEqual(record?.correctionSource, "alternative")
        XCTAssertTrue(visit.placeConfirmed)
    }
}
