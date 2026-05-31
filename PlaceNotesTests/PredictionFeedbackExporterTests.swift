import XCTest
@testable import PlaceNotes

final class PredictionFeedbackExporterTests: XCTestCase {

    private func makeRecord(
        predictedName: String = "Blue Bottle",
        verdict: PredictionVerdict = .accurate,
        correctedName: String? = nil,
        correctionSource: String? = nil
    ) -> PredictionFeedback {
        PredictionFeedback(
            visitID: UUID(),
            arrivalDate: Date(timeIntervalSince1970: 0),
            predictedPlaceName: predictedName,
            predictedCategory: "Cafe",
            confidenceRaw: PlaceConfidence.high.rawValue,
            medianAccuracyMeters: 12.5,
            alternativeCount: 2,
            latitude: 37.78,
            longitude: -122.41,
            verdict: verdict,
            correctedName: correctedName,
            correctedCategory: nil,
            correctionSource: correctionSource,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func csvString(_ records: [PredictionFeedback]) -> String {
        String(data: PredictionFeedbackExporter.exportCSV(from: records), encoding: .utf8) ?? ""
    }

    func testEmptyExportContainsHeaderOnly() {
        let csv = csvString([])
        XCTAssertEqual(csv, PredictionFeedbackExporter.header)
    }

    func testRowCountMatchesRecords() {
        let csv = csvString([makeRecord(), makeRecord(), makeRecord()])
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 4) // header + 3 rows
    }

    func testAccurateVerdictEncodesLabelOne() {
        let csv = csvString([makeRecord(verdict: .accurate)])
        let row = csv.split(separator: "\n")[1]
        XCTAssertTrue(row.contains(",accurate,1,"))
    }

    func testWrongVerdictEncodesLabelZero() {
        let csv = csvString([makeRecord(verdict: .wrong)])
        let row = csv.split(separator: "\n")[1]
        XCTAssertTrue(row.contains(",wrong,0,"))
    }

    func testCorrectedVerdictEncodesLabelZeroAndCorrection() {
        let csv = csvString([makeRecord(verdict: .corrected, correctedName: "Philz Coffee", correctionSource: "alternative")])
        let row = csv.split(separator: "\n")[1]
        XCTAssertTrue(row.contains(",corrected,0,"))
        XCTAssertTrue(row.contains("Philz Coffee"))
        XCTAssertTrue(row.contains("alternative"))
    }

    func testNameWithCommaIsQuoted() {
        let csv = csvString([makeRecord(predictedName: "Joe's Diner, Inc")])
        XCTAssertTrue(csv.contains("\"Joe's Diner, Inc\""))
    }

    func testNameWithQuoteIsEscaped() {
        let csv = csvString([makeRecord(predictedName: "The \"Best\" Spot")])
        XCTAssertTrue(csv.contains("\"The \"\"Best\"\" Spot\""))
    }
}
