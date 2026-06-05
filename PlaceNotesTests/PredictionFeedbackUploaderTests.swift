import XCTest
import Foundation
@testable import PlaceNotes

final class PredictionFeedbackUploaderTests: XCTestCase {
    private final class StubHTTPSession: PredictionFeedbackHTTPSession {
        var receivedRequest: URLRequest?
        var result: Result<(Data, URLResponse), Error>

        init(result: Result<(Data, URLResponse), Error>) {
            self.result = result
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            receivedRequest = request
            return try result.get()
        }
    }

    private func makePayload(verdict: PredictionVerdict = .accurate) -> PredictionFeedbackUploadPayload {
        let record = PredictionFeedback(
            visitID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            arrivalDate: Date(timeIntervalSince1970: 1_700_000_000),
            predictedPlaceName: "Blue Bottle",
            predictedCategory: "Cafe",
            confidenceRaw: "High",
            medianAccuracyMeters: 14,
            alternativeCount: 1,
            latitude: 37.78,
            longitude: -122.41,
            verdict: verdict,
            correctedName: nil,
            correctedCategory: nil,
            correctionSource: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        return PredictionFeedbackUploadPayload(record: record, bundle: Bundle(for: Self.self))
    }

    func testUploadPostsJSONToAzureFunctionEndpoint() async throws {
        let endpoint = URL(string: "https://example.test/api/feedback")!
        let response = HTTPURLResponse(url: endpoint, statusCode: 202, httpVersion: nil, headerFields: nil)!
        let session = StubHTTPSession(result: .success((Data(), response)))

        let result = await PredictionFeedbackUploader.upload(makePayload(), endpoint: endpoint, session: session)

        XCTAssertEqual(result, .success)
        let request = try XCTUnwrap(session.receivedRequest)
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["buildConfiguration"] as? String, "debug")
        XCTAssertEqual(json["predictedPlaceName"] as? String, "Blue Bottle")
        XCTAssertEqual(json["verdict"] as? String, "accurate")
        XCTAssertEqual(json["wasAccurate"] as? Bool, true)
    }

    func testUploadTreatsNoInternetAsRecoverableNetworkUnavailable() async {
        let endpoint = URL(string: "https://example.test/api/feedback")!
        let session = StubHTTPSession(result: .failure(URLError(.notConnectedToInternet)))

        let result = await PredictionFeedbackUploader.upload(makePayload(), endpoint: endpoint, session: session)

        guard case .networkUnavailable = result else {
            XCTFail("Expected networkUnavailable, got \(result)")
            return
        }
    }

    func testUploadSummarizesPartialNetworkFailures() async {
        let endpoint = URL(string: "https://example.test/api/feedback")!
        let session = StubHTTPSession(result: .failure(URLError(.timedOut)))

        let summary = await PredictionFeedbackUploader.upload(
            [makePayload(), makePayload(verdict: .wrong)],
            endpoint: endpoint,
            session: session
        )

        XCTAssertEqual(summary.succeeded, 0)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.networkUnavailable, 2)
        XCTAssertEqual(summary.displayText, "No internet: 2 pending")
    }

    func testBatchUploadPostsJSONArrayOnce() async throws {
        let endpoint = URL(string: "https://example.test/api/feedback")!
        let response = HTTPURLResponse(url: endpoint, statusCode: 202, httpVersion: nil, headerFields: nil)!
        let session = StubHTTPSession(result: .success((Data(), response)))

        let summary = await PredictionFeedbackUploader.upload(
            [makePayload(), makePayload(verdict: .wrong)],
            endpoint: endpoint,
            session: session
        )

        XCTAssertEqual(summary.succeeded, 2)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.networkUnavailable, 0)

        let request = try XCTUnwrap(session.receivedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        XCTAssertEqual(json.count, 2)
        XCTAssertEqual(json.first?["buildConfiguration"] as? String, "debug")
        XCTAssertEqual(json.first?["verdict"] as? String, "accurate")
        XCTAssertEqual(json.last?["verdict"] as? String, "wrong")
    }
}
