import XCTest
import CoreLocation
@testable import PlaceNotes

final class KDEKernelTests: XCTestCase {
    private let bandwidth = 100.0   // meters

    func testZeroPointsReturnsZero() {
        let value = KDEKernel.evaluate(
            at: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.41),
            points: [],
            bandwidthMeters: bandwidth
        )
        XCTAssertEqual(value, 0, accuracy: 1e-9)
    }

    func testSinglePointMaxAtSelf() {
        let coord = CLLocationCoordinate2D(latitude: 37.78, longitude: -122.41)
        let p = WeightedPoint(coordinate: coord, weight: 10)
        let atSelf = KDEKernel.evaluate(at: coord, points: [p], bandwidthMeters: bandwidth)
        let nearby = CLLocationCoordinate2D(latitude: 37.7805, longitude: -122.41)
        let off = KDEKernel.evaluate(at: nearby, points: [p], bandwidthMeters: bandwidth)
        XCTAssertGreaterThan(atSelf, off)
    }

    func testMonotoneDecayWithDistance() {
        let center = CLLocationCoordinate2D(latitude: 37.78, longitude: -122.41)
        let p = WeightedPoint(coordinate: center, weight: 1)
        let near = CLLocationCoordinate2D(latitude: 37.7805, longitude: -122.41)
        let far  = CLLocationCoordinate2D(latitude: 37.781, longitude: -122.41)
        let v1 = KDEKernel.evaluate(at: near, points: [p], bandwidthMeters: bandwidth)
        let v2 = KDEKernel.evaluate(at: far, points: [p], bandwidthMeters: bandwidth)
        XCTAssertGreaterThan(v1, v2)
    }

    func testTwoPointsMidpointBetweenEachAndSum() {
        let a = CLLocationCoordinate2D(latitude: 37.78, longitude: -122.41)
        let b = CLLocationCoordinate2D(latitude: 37.781, longitude: -122.41)
        let mid = CLLocationCoordinate2D(latitude: 37.7805, longitude: -122.41)
        let pa = WeightedPoint(coordinate: a, weight: 1)
        let pb = WeightedPoint(coordinate: b, weight: 1)
        let atMid = KDEKernel.evaluate(at: mid, points: [pa, pb], bandwidthMeters: 200)
        let atA = KDEKernel.evaluate(at: a, points: [pa], bandwidthMeters: 200)
        XCTAssertGreaterThan(atMid, atA * 0.5)
        XCTAssertLessThanOrEqual(atMid, atA + atA)
    }

    func testWeightScalingLinear() {
        let c = CLLocationCoordinate2D(latitude: 37.78, longitude: -122.41)
        let p1 = WeightedPoint(coordinate: c, weight: 1)
        let p2 = WeightedPoint(coordinate: c, weight: 2)
        let v1 = KDEKernel.evaluate(at: c, points: [p1], bandwidthMeters: bandwidth)
        let v2 = KDEKernel.evaluate(at: c, points: [p2], bandwidthMeters: bandwidth)
        XCTAssertEqual(v2, v1 * 2, accuracy: 1e-9)
    }
}
