#if DEBUG
import Foundation
import os

struct PredictionFeedbackUploadPayload: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let appVersion: String
    let appBuild: String
    let buildConfiguration: String
    let eventID: UUID
    let createdAt: String
    let visitID: UUID
    let arrivalDate: String
    let latitude: Double
    let longitude: Double
    let predictedPlaceName: String
    let predictedCategory: String?
    let confidence: String
    let medianAccuracyMeters: Double?
    let alternativeCount: Int
    let verdict: String
    let wasAccurate: Bool
    let correctedPlaceName: String?
    let correctedCategory: String?
    let correctionSource: String?

    init(record: PredictionFeedback, bundle: Bundle = .main) {
        self.schemaVersion = 1
        self.appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        self.appBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        self.buildConfiguration = "debug"
        self.eventID = record.id
        self.createdAt = Self.iso8601String(from: record.createdAt)
        self.visitID = record.visitID
        self.arrivalDate = Self.iso8601String(from: record.arrivalDate)
        self.latitude = record.latitude
        self.longitude = record.longitude
        self.predictedPlaceName = record.predictedPlaceName
        self.predictedCategory = record.predictedCategory
        self.confidence = record.confidenceRaw
        self.medianAccuracyMeters = record.medianAccuracyMeters
        self.alternativeCount = record.alternativeCount
        self.verdict = record.verdict.rawValue
        self.wasAccurate = record.verdict.wasAccurate
        self.correctedPlaceName = record.correctedPlaceName
        self.correctedCategory = record.correctedCategory
        self.correctionSource = record.correctionSource
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

enum PredictionFeedbackUploadResult: Equatable, Sendable {
    case success
    case networkUnavailable(String)
    case serverRejected(statusCode: Int, body: String)
    case failed(String)
}

struct PredictionFeedbackUploadSummary: Equatable, Sendable {
    var succeeded: Int
    var failed: Int
    var networkUnavailable: Int

    var displayText: String {
        if failed == 0 && networkUnavailable == 0 {
            return "Uploaded \(succeeded)"
        }
        if networkUnavailable > 0 {
            return "No internet: \(networkUnavailable) pending"
        }
        return "Uploaded \(succeeded), failed \(failed)"
    }
}

protocol PredictionFeedbackHTTPSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: PredictionFeedbackHTTPSession {}

enum PredictionFeedbackUploader {
    static let endpoint = URL(string: "https://func-placelore-feedback-dev.azurewebsites.net/api/feedback")!

    private static let logger = Logger(subsystem: "dev.placelore.app", category: "PredictionFeedbackUpload")
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func upload(
        _ payload: PredictionFeedbackUploadPayload,
        endpoint: URL = Self.endpoint,
        session: PredictionFeedbackHTTPSession = URLSession.shared
    ) async -> PredictionFeedbackUploadResult {
        do {
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try makeEncoder().encode(payload)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Prediction feedback upload failed: non-HTTP response")
                return .failed("Non-HTTP response")
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                logger.error("Prediction feedback upload rejected: \(httpResponse.statusCode)")
                return .serverRejected(statusCode: httpResponse.statusCode, body: body)
            }

            logger.debug("Prediction feedback uploaded: \(payload.eventID.uuidString)")
            return .success
        } catch let error as URLError {
            if error.isNetworkUnavailable {
                logger.warning("Prediction feedback upload deferred, network unavailable: \(error.localizedDescription)")
                return .networkUnavailable(error.localizedDescription)
            }
            logger.error("Prediction feedback upload failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        } catch {
            logger.error("Prediction feedback upload failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    static func upload(
        _ payloads: [PredictionFeedbackUploadPayload],
        endpoint: URL = Self.endpoint,
        session: PredictionFeedbackHTTPSession = URLSession.shared
    ) async -> PredictionFeedbackUploadSummary {
        var summary = PredictionFeedbackUploadSummary(succeeded: 0, failed: 0, networkUnavailable: 0)
        for payload in payloads {
            switch await upload(payload, endpoint: endpoint, session: session) {
            case .success:
                summary.succeeded += 1
            case .networkUnavailable:
                summary.networkUnavailable += 1
            case .serverRejected, .failed:
                summary.failed += 1
            }
        }
        return summary
    }
}

private extension URLError {
    var isNetworkUnavailable: Bool {
        switch code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .timedOut:
            return true
        default:
            return false
        }
    }
}
#endif
