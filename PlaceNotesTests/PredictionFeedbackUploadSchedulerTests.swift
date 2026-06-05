import XCTest
import SwiftData
@testable import PlaceNotes

@MainActor
final class PredictionFeedbackUploadSchedulerTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Place.self, Visit.self, JournalEntry.self, CustomCategory.self,
            RawLocationSample.self, PredictionFeedback.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func insertFeedback(count: Int, in context: ModelContext) throws {
        for index in 0..<count {
            let record = PredictionFeedback(
                visitID: UUID(),
                arrivalDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                predictedPlaceName: "Place \(index)",
                predictedCategory: "Cafe",
                confidenceRaw: "High",
                medianAccuracyMeters: 10,
                alternativeCount: 0,
                latitude: 37.78,
                longitude: -122.41,
                verdict: .accurate,
                createdAt: Date(timeIntervalSince1970: 1_700_000_100 + Double(index))
            )
            context.insert(record)
        }
        try context.save()
    }

    private func allFeedback(_ context: ModelContext) -> [PredictionFeedback] {
        let descriptor = FetchDescriptor<PredictionFeedback>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func testUploadPendingMarksSuccessfulBatchUploaded() async throws {
        let context = try makeContext()
        try insertFeedback(count: 2, in: context)

        let summary = await PredictionFeedbackUploadScheduler.uploadPendingFeedback(in: context) { payloads in
            XCTAssertEqual(payloads.count, 2)
            return PredictionFeedbackUploadSummary(succeeded: payloads.count, failed: 0, networkUnavailable: 0)
        }

        XCTAssertEqual(summary.succeeded, 2)
        let records = allFeedback(context)
        XCTAssertTrue(records.allSatisfy { $0.uploadedAt != nil })
        XCTAssertTrue(records.allSatisfy { $0.uploadAttemptCount == 1 })
        XCTAssertTrue(records.allSatisfy { $0.lastUploadError == nil })
    }

    func testUploadPendingKeepsNetworkFailuresPending() async throws {
        let context = try makeContext()
        try insertFeedback(count: 2, in: context)

        let summary = await PredictionFeedbackUploadScheduler.uploadPendingFeedback(in: context) { payloads in
            PredictionFeedbackUploadSummary(succeeded: 0, failed: 0, networkUnavailable: payloads.count)
        }

        XCTAssertEqual(summary.networkUnavailable, 2)
        let records = allFeedback(context)
        XCTAssertTrue(records.allSatisfy { $0.uploadedAt == nil })
        XCTAssertTrue(records.allSatisfy { $0.uploadAttemptCount == 1 })
        XCTAssertTrue(records.allSatisfy { $0.lastUploadError == "networkUnavailable" })
    }

    func testUploadPendingHonorsBatchSize() async throws {
        let context = try makeContext()
        try insertFeedback(count: 3, in: context)

        let summary = await PredictionFeedbackUploadScheduler.uploadPendingFeedback(in: context, batchSize: 2) { payloads in
            XCTAssertEqual(payloads.count, 2)
            return PredictionFeedbackUploadSummary(succeeded: payloads.count, failed: 0, networkUnavailable: 0)
        }

        XCTAssertEqual(summary.succeeded, 2)
        let records = allFeedback(context)
        XCTAssertEqual(records.filter { $0.uploadedAt != nil }.count, 2)
        XCTAssertEqual(records.filter { $0.uploadedAt == nil }.count, 1)
    }
}
