import Foundation
import SwiftData
import os

private enum PredictionFeedbackUploadScheduleDefaults {
    static let uploadInterval: TimeInterval = 15 * 60
    static let batchSize = 50
}

@MainActor
final class PredictionFeedbackUploadScheduler {
    static let defaultUploadInterval = PredictionFeedbackUploadScheduleDefaults.uploadInterval
    static let defaultBatchSize = PredictionFeedbackUploadScheduleDefaults.batchSize

    private let context: ModelContext
    private let uploadInterval: TimeInterval
    private let batchSize: Int
    private var timer: Timer?
    private var isUploading = false

    private let logger = Logger(subsystem: "dev.placelore.app", category: "PredictionFeedbackUpload")

    init(
        context: ModelContext,
        uploadInterval: TimeInterval = PredictionFeedbackUploadScheduleDefaults.uploadInterval,
        batchSize: Int = PredictionFeedbackUploadScheduleDefaults.batchSize
    ) {
        self.context = context
        self.uploadInterval = uploadInterval
        self.batchSize = batchSize
    }

    func start() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: uploadInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.uploadPending()
            }
        }

        Task { @MainActor in
            await uploadPending()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func uploadPending() async {
        guard !isUploading else { return }
        isUploading = true
        defer { isUploading = false }

        let summary = await Self.uploadPendingFeedback(in: context, batchSize: batchSize)
        if summary.succeeded > 0 || summary.failed > 0 || summary.networkUnavailable > 0 {
            logger.info(
                "Prediction feedback batch upload finished. succeeded=\(summary.succeeded), failed=\(summary.failed), networkUnavailable=\(summary.networkUnavailable)"
            )
        }
    }

    static func uploadPendingFeedback(
        in context: ModelContext,
        batchSize: Int = PredictionFeedbackUploadScheduleDefaults.batchSize,
        now: Date = Date(),
        uploader: ([PredictionFeedbackUploadPayload]) async -> PredictionFeedbackUploadSummary = {
            await PredictionFeedbackUploader.upload($0)
        }
    ) async -> PredictionFeedbackUploadSummary {
        var descriptor = FetchDescriptor<PredictionFeedback>(
            predicate: #Predicate { $0.uploadedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = batchSize

        let records = (try? context.fetch(descriptor)) ?? []
        guard !records.isEmpty else {
            return PredictionFeedbackUploadSummary(succeeded: 0, failed: 0, networkUnavailable: 0)
        }

        for record in records {
            record.uploadAttemptCount += 1
            record.lastUploadAttemptAt = now
            record.lastUploadError = nil
        }
        try? context.save()

        let payloads = records.map { PredictionFeedbackUploadPayload(record: $0) }
        let summary = await uploader(payloads)
        let finishedAt = Date()

        if summary.succeeded == records.count && summary.failed == 0 && summary.networkUnavailable == 0 {
            for record in records {
                record.uploadedAt = finishedAt
                record.lastUploadError = nil
            }
        } else {
            let error: String
            if summary.networkUnavailable > 0 {
                error = "networkUnavailable"
            } else {
                error = "uploadFailed"
            }
            for record in records {
                record.lastUploadError = error
            }
        }

        try? context.save()
        return summary
    }
}
