import Foundation
import SwiftData
import os

/// Persists user feedback on place-prediction accuracy as labeled
/// `PredictionFeedback` records for offline analysis and future model training.
///
/// One record exists per visit: re-submitting feedback replaces the previous
/// record so the exported dataset holds a single labeled example per visit.
enum PredictionFeedbackRecorder {
    private static let logger = Logger(subsystem: "dev.placelore.app", category: "PredictionFeedback")

    @MainActor
    static func record(
        _ verdict: PredictionVerdict,
        for visit: Visit,
        correctedName: String? = nil,
        correctedCategory: String? = nil,
        correctionSource: String? = nil,
        in context: ModelContext
    ) {
        // Single chokepoint: when the feedback feature is off, no record is
        // written regardless of which caller invoked this (Logbook verdicts,
        // the picker, or a place reassignment via AlternativePlacePicker).
        guard AppSettings.shared.predictionFeedbackEnabled else { return }

        let visitID = visit.id
        let descriptor = FetchDescriptor<PredictionFeedback>(
            predicate: #Predicate { $0.visitID == visitID }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        for record in existing {
            context.delete(record)
        }

        let predicted = visit.place
        let feedback = PredictionFeedback(
            visitID: visit.id,
            arrivalDate: visit.arrivalDate,
            predictedPlaceName: predicted?.name ?? "Unknown",
            predictedCategory: predicted?.category,
            confidenceRaw: visit.confidence.rawValue,
            medianAccuracyMeters: visit.medianAccuracyMeters,
            alternativeCount: visit.alternativePlaces.count,
            latitude: predicted?.latitude ?? 0,
            longitude: predicted?.longitude ?? 0,
            verdict: verdict,
            correctedName: correctedName,
            correctedCategory: correctedCategory,
            correctionSource: correctionSource
        )
        context.insert(feedback)

        // An unresolved "wrong" means the place is still unconfirmed; accurate
        // and corrected verdicts are deliberate confirmations.
        visit.placeConfirmed = verdict != .wrong

        do {
            try context.save()
        } catch {
            logger.error("Failed to save prediction feedback: \(error.localizedDescription)")
        }
    }
}
