import XCTest
import SwiftUI
import UIKit
@testable import PlaceNotes

final class TrajectoryPolylineTests: XCTestCase {

    // Reference stops from TrajectoryPolyline.timeColor.
    private let amYellow = (r: 251.0/255, g: 191.0/255, b: 36.0/255)
    private let pmOrange = (r: 251.0/255, g: 146.0/255, b: 60.0/255)
    private let evePurple = (r: 124.0/255, g: 58.0/255, b: 237.0/255)

    // MARK: - Helpers

    private func components(_ color: Color) -> (r: Double, g: Double, b: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    private func assertColor(
        _ color: Color,
        equals expected: (r: Double, g: Double, b: Double),
        accuracy: Double = 1.0/255,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let actual = components(color)
        XCTAssertEqual(actual.r, expected.r, accuracy: accuracy, "red", file: file, line: line)
        XCTAssertEqual(actual.g, expected.g, accuracy: accuracy, "green", file: file, line: line)
        XCTAssertEqual(actual.b, expected.b, accuracy: accuracy, "blue", file: file, line: line)
    }

    // MARK: - Endpoint colors

    func testTimeColorAtZeroIsAmYellow() {
        assertColor(TrajectoryPolyline.timeColor(normalized: 0.0), equals: amYellow)
    }

    func testTimeColorAtMidpointIsPmOrange() {
        // The branch is `if clamped < 0.5`, so 0.5 falls into the upper branch
        // with t2 = 0, producing exactly pmOrange. Pins continuity at the seam.
        assertColor(TrajectoryPolyline.timeColor(normalized: 0.5), equals: pmOrange)
    }

    func testTimeColorAtOneIsEvePurple() {
        assertColor(TrajectoryPolyline.timeColor(normalized: 1.0), equals: evePurple)
    }

    // MARK: - Interpolation midpoints

    func testTimeColorAtQuarterIsAmOrangeMidpoint() {
        // t = 0.25 → t2 = 0.5 in the lower branch → halfway between amYellow and pmOrange.
        let expected = (
            r: (amYellow.r + pmOrange.r) / 2,
            g: (amYellow.g + pmOrange.g) / 2,
            b: (amYellow.b + pmOrange.b) / 2
        )
        assertColor(TrajectoryPolyline.timeColor(normalized: 0.25), equals: expected)
    }

    func testTimeColorAtThreeQuartersIsPmEveMidpoint() {
        // t = 0.75 → t2 = 0.5 in the upper branch → halfway between pmOrange and evePurple.
        let expected = (
            r: (pmOrange.r + evePurple.r) / 2,
            g: (pmOrange.g + evePurple.g) / 2,
            b: (pmOrange.b + evePurple.b) / 2
        )
        assertColor(TrajectoryPolyline.timeColor(normalized: 0.75), equals: expected)
    }

    // MARK: - Clamping

    func testTimeColorBelowZeroClampsToAmYellow() {
        assertColor(TrajectoryPolyline.timeColor(normalized: -0.5), equals: amYellow)
    }

    func testTimeColorAboveOneClampsToEvePurple() {
        assertColor(TrajectoryPolyline.timeColor(normalized: 1.5), equals: evePurple)
    }
}
