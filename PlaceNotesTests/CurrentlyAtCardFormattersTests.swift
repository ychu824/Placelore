import XCTest
import CoreLocation
@testable import PlaceNotes

final class CurrentlyAtCardFormattersTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // Microsoft Building 109 / Overlake area
    private let placeLat = 47.6446
    private let placeLon = -122.1390

    func testIsUserAtPlaceTrueWhenUserLocationUnknown() {
        XCTAssertTrue(
            CurrentlyAtFormatter.isUserAtPlace(
                userLocation: nil,
                placeLatitude: placeLat,
                placeLongitude: placeLon
            )
        )
    }

    func testIsUserAtPlaceTrueWhenUserIsAtPlace() {
        let user = CLLocationCoordinate2D(latitude: placeLat, longitude: placeLon)
        XCTAssertTrue(
            CurrentlyAtFormatter.isUserAtPlace(
                userLocation: user,
                placeLatitude: placeLat,
                placeLongitude: placeLon
            )
        )
    }

    func testIsUserAtPlaceTrueWhenWithinThreshold() {
        // ~50m north of the place — well within the 150m default threshold.
        let user = CLLocationCoordinate2D(
            latitude: placeLat + 0.00045,
            longitude: placeLon
        )
        XCTAssertTrue(
            CurrentlyAtFormatter.isUserAtPlace(
                userLocation: user,
                placeLatitude: placeLat,
                placeLongitude: placeLon
            )
        )
    }

    func testIsUserAtPlaceFalseWhenBeyondThreshold() {
        // ~500m east of the place — well outside the 150m default threshold.
        let user = CLLocationCoordinate2D(
            latitude: placeLat,
            longitude: placeLon + 0.0067
        )
        XCTAssertFalse(
            CurrentlyAtFormatter.isUserAtPlace(
                userLocation: user,
                placeLatitude: placeLat,
                placeLongitude: placeLon
            )
        )
    }

    func testIsUserAtPlaceHonorsCustomThreshold() {
        // ~200m north — outside 150m default but inside an explicit 300m override.
        let user = CLLocationCoordinate2D(
            latitude: placeLat + 0.0018,
            longitude: placeLon
        )
        XCTAssertFalse(
            CurrentlyAtFormatter.isUserAtPlace(
                userLocation: user,
                placeLatitude: placeLat,
                placeLongitude: placeLon
            )
        )
        XCTAssertTrue(
            CurrentlyAtFormatter.isUserAtPlace(
                userLocation: user,
                placeLatitude: placeLat,
                placeLongitude: placeLon,
                thresholdMeters: 300
            )
        )
    }

    func testElapsedUnderOneMinuteReadsJustArrived() {
        let now = base.addingTimeInterval(45)
        XCTAssertEqual(
            CurrentlyAtFormatter.elapsed(arrivalDate: base, now: now),
            String(localized: "Just arrived")
        )
    }

    func testElapsedAtFiftyNineSecondsStillJustArrived() {
        let now = base.addingTimeInterval(59)
        XCTAssertEqual(
            CurrentlyAtFormatter.elapsed(arrivalDate: base, now: now),
            String(localized: "Just arrived")
        )
    }

    func testElapsedAtOneMinuteShowsMinutes() {
        let now = base.addingTimeInterval(60)
        let expected = String(format: String(localized: "Arrived %lldm ago"), 1)
        XCTAssertEqual(CurrentlyAtFormatter.elapsed(arrivalDate: base, now: now), expected)
    }

    func testElapsedAtFiftyNineMinutesShowsMinutes() {
        let now = base.addingTimeInterval(59 * 60)
        let expected = String(format: String(localized: "Arrived %lldm ago"), 59)
        XCTAssertEqual(CurrentlyAtFormatter.elapsed(arrivalDate: base, now: now), expected)
    }

    func testElapsedAtOneHourShowsHoursAndMinutes() {
        let now = base.addingTimeInterval(3600 + 720)   // 1h 12m
        let expected = String(format: String(localized: "Arrived %lldh %lldm ago"), 1, 12)
        XCTAssertEqual(CurrentlyAtFormatter.elapsed(arrivalDate: base, now: now), expected)
    }

    func testElapsedAtTwentyThreeHoursShowsHoursAndMinutes() {
        let now = base.addingTimeInterval(23 * 3600 + 59 * 60)
        let expected = String(format: String(localized: "Arrived %lldh %lldm ago"), 23, 59)
        XCTAssertEqual(CurrentlyAtFormatter.elapsed(arrivalDate: base, now: now), expected)
    }

    func testPriorVisitsZeroReadsFirstVisit() {
        XCTAssertEqual(CurrentlyAtFormatter.priorVisits(0), String(localized: "First visit here"))
    }

    func testPriorVisitsOneIsSingular() {
        let expected = String(format: String(localized: "%lld prior visit"), 1)
        XCTAssertEqual(CurrentlyAtFormatter.priorVisits(1), expected)
    }

    func testPriorVisitsManyIsPlural() {
        let expected = String(format: String(localized: "%lld prior visits"), 22)
        XCTAssertEqual(CurrentlyAtFormatter.priorVisits(22), expected)
    }

    func testPriorVisitsNegativeClampsToFirst() {
        XCTAssertEqual(CurrentlyAtFormatter.priorVisits(-1), String(localized: "First visit here"))
    }

    // MARK: - Live Activity (Dynamic Island) content state

    func testActivityTitleFallsBackToAppNameWhenNoPlace() {
        let state = CaptureActivityAttributes.ContentState(placeName: nil)
        XCTAssertEqual(state.title, "Placelore")
    }

    func testActivityTitleUsesNameWhenEmojiMissing() {
        let state = CaptureActivityAttributes.ContentState(placeName: "Blue Bottle")
        XCTAssertEqual(state.title, "Blue Bottle")
    }

    func testActivityTitleCombinesEmojiAndName() {
        let state = CaptureActivityAttributes.ContentState(placeName: "Blue Bottle", placeEmoji: "☕️")
        XCTAssertEqual(state.title, "☕️ Blue Bottle")
    }

    func testActivityPriorVisitsTextMirrorsCard() {
        XCTAssertEqual(CaptureActivityAttributes.ContentState(placeName: "X", priorVisitCount: 0).priorVisitsText, "First visit here")
        XCTAssertEqual(CaptureActivityAttributes.ContentState(placeName: "X", priorVisitCount: 1).priorVisitsText, "1 prior visit")
        XCTAssertEqual(CaptureActivityAttributes.ContentState(placeName: "X", priorVisitCount: 7).priorVisitsText, "7 prior visits")
    }

    func testActivityPriorVisitsTextClampsNegative() {
        XCTAssertEqual(CaptureActivityAttributes.ContentState(placeName: "X", priorVisitCount: -3).priorVisitsText, "First visit here")
    }
}
