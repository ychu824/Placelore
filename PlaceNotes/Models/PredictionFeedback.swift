#if DEBUG
import Foundation
import SwiftData

/// The user's verdict on how accurately a visit was resolved to a place.
/// - accurate: The predicted place was correct.
/// - wrong: The predicted place was wrong and the user did not supply a correction.
/// - corrected: The predicted place was wrong and the user picked the right one.
enum PredictionVerdict: String, Codable, CaseIterable {
    case accurate
    case wrong
    case corrected

    /// Binary training label: the prediction was correct as produced by the algorithm.
    var wasAccurate: Bool { self == .accurate }
}

/// A labeled record of a single place-prediction outcome, capturing the
/// prediction's features at the time it was made alongside the user's verdict.
///
/// One record exists per visit (re-submitting feedback replaces it). The rows
/// are exported as CSV for offline analysis of prediction quality and as a
/// training set for a future model.
@Model
final class PredictionFeedback {
    var id: UUID
    var createdAt: Date

    /// The visit this feedback is about. Stored as the visit's UUID rather than
    /// a relationship so a record survives independently for export.
    var visitID: UUID
    var arrivalDate: Date

    // MARK: Prediction snapshot (features)

    var predictedPlaceName: String
    var predictedCategory: String?
    /// Confidence the algorithm assigned at prediction time (High/Medium/Low).
    var confidenceRaw: String
    var medianAccuracyMeters: Double?
    /// Number of runner-up POI candidates the algorithm found.
    var alternativeCount: Int
    var latitude: Double
    var longitude: Double

    // MARK: User verdict (label)

    var verdictRaw: String
    var correctedPlaceName: String?
    var correctedCategory: String?
    /// How the correction was supplied: "alternative" | "search" | nil.
    var correctionSource: String?

    var verdict: PredictionVerdict {
        get { PredictionVerdict(rawValue: verdictRaw) ?? .wrong }
        set { verdictRaw = newValue.rawValue }
    }

    init(
        visitID: UUID,
        arrivalDate: Date,
        predictedPlaceName: String,
        predictedCategory: String?,
        confidenceRaw: String,
        medianAccuracyMeters: Double?,
        alternativeCount: Int,
        latitude: Double,
        longitude: Double,
        verdict: PredictionVerdict,
        correctedName: String? = nil,
        correctedCategory: String? = nil,
        correctionSource: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.createdAt = createdAt
        self.visitID = visitID
        self.arrivalDate = arrivalDate
        self.predictedPlaceName = predictedPlaceName
        self.predictedCategory = predictedCategory
        self.confidenceRaw = confidenceRaw
        self.medianAccuracyMeters = medianAccuracyMeters
        self.alternativeCount = alternativeCount
        self.latitude = latitude
        self.longitude = longitude
        self.verdictRaw = verdict.rawValue
        self.correctedPlaceName = correctedName
        self.correctedCategory = correctedCategory
        self.correctionSource = correctionSource
    }
}
#endif
