import XCTest
@testable import PlaceNotes

final class PullProgressTests: XCTestCase {

    // MARK: - progress(distance:threshold:)

    func testProgressClampsToZeroForNegativeDistance() {
        XCTAssertEqual(PullProgress.progress(distance: -10, threshold: 120), 0)
    }

    func testProgressIsZeroAtZeroDistance() {
        XCTAssertEqual(PullProgress.progress(distance: 0, threshold: 120), 0)
    }

    func testProgressIsHalfAtHalfThreshold() {
        XCTAssertEqual(PullProgress.progress(distance: 60, threshold: 120), 0.5, accuracy: 0.0001)
    }

    func testProgressIsOneAtThreshold() {
        XCTAssertEqual(PullProgress.progress(distance: 120, threshold: 120), 1.0)
    }

    func testProgressClampsToOneBeyondThreshold() {
        XCTAssertEqual(PullProgress.progress(distance: 1_000, threshold: 120), 1.0)
    }

    func testProgressReturnsZeroWhenThresholdIsZeroOrNegative() {
        XCTAssertEqual(PullProgress.progress(distance: 50, threshold: 0), 0)
        XCTAssertEqual(PullProgress.progress(distance: 50, threshold: -1), 0)
    }

    // MARK: - didCrossThreshold(old:new:)

    func testDidCrossThresholdFiresOnRisingEdge() {
        XCTAssertTrue(PullProgress.didCrossThreshold(old: 0.99, new: 1.0))
        XCTAssertTrue(PullProgress.didCrossThreshold(old: 0.0, new: 1.0))
    }

    func testDidCrossThresholdDoesNotFireBelow() {
        XCTAssertFalse(PullProgress.didCrossThreshold(old: 0.5, new: 0.9))
    }

    func testDidCrossThresholdDoesNotFireWhenAlreadyAtThreshold() {
        XCTAssertFalse(PullProgress.didCrossThreshold(old: 1.0, new: 1.0))
    }

    func testDidCrossThresholdDoesNotFireOnFallingEdge() {
        XCTAssertFalse(PullProgress.didCrossThreshold(old: 1.0, new: 0.5))
    }
}
