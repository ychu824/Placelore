#if DEBUG
import Foundation

/// Builds a CSV dataset from `PredictionFeedback` records for offline analysis
/// (pandas / scikit-learn) and as a training set for a future prediction model.
///
/// Each row is one labeled example: prediction features plus the binary
/// `wasAccurate` label and the user's correction when supplied.
enum PredictionFeedbackExporter {
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let header = "id,createdAt,visitID,arrivalDate,latitude,longitude,predictedPlaceName,predictedCategory,confidence,medianAccuracyMeters,alternativeCount,verdict,wasAccurate,correctedPlaceName,correctedCategory,correctionSource"

    static func exportCSV(from records: [PredictionFeedback]) -> Data {
        var lines = [header]
        for r in records {
            let row: [String] = [
                r.id.uuidString,
                iso8601.string(from: r.createdAt),
                r.visitID.uuidString,
                iso8601.string(from: r.arrivalDate),
                "\(r.latitude)",
                "\(r.longitude)",
                escape(r.predictedPlaceName),
                escape(r.predictedCategory),
                r.confidenceRaw,
                r.medianAccuracyMeters.map { "\($0)" } ?? "",
                "\(r.alternativeCount)",
                r.verdict.rawValue,
                r.verdict.wasAccurate ? "1" : "0",
                escape(r.correctedPlaceName),
                escape(r.correctedCategory),
                escape(r.correctionSource)
            ]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    /// Wraps a value in quotes and doubles inner quotes when it contains a
    /// comma, quote, or newline — keeps free-text place names CSV-safe.
    private static func escape(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
#endif
