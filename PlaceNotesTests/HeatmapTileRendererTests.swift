import XCTest
import CoreLocation
import MapKit
import UIKit
@testable import PlaceNotes

final class HeatmapTileRendererTests: XCTestCase {

    private func loadTile(_ renderer: HeatmapTileRenderer, x: Int, y: Int, z: Int) -> Data? {
        var result: Data? = nil
        let exp = expectation(description: "loadTile")
        renderer.loadTile(at: MKTileOverlayPath(x: x, y: y, z: z, contentScaleFactor: 1)) { data, _ in
            result = data
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        return result
    }

    func testEmptyKernelReturnsNilTile() {
        let renderer = HeatmapTileRenderer(points: [], style: .light)
        let data = loadTile(renderer, x: 0, y: 0, z: 16)
        XCTAssertNil(data)
    }

    func testNonEmptyKernelReturnsPNGTile() {
        let point = WeightedPoint(
            coordinate: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.41),
            weight: 60
        )
        let renderer = HeatmapTileRenderer(points: [point], style: .light)

        // tile covering SF at z=12 (rough)
        let z = 12
        let tileX = Int(((point.coordinate.longitude + 180) / 360) * pow(2.0, Double(z)))
        let latRad = point.coordinate.latitude * .pi / 180
        let tileY = Int((1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * pow(2.0, Double(z)))
        let data = loadTile(renderer, x: tileX, y: tileY, z: z)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
    }

    func testLightAndDarkProduceDifferentBytes() {
        let point = WeightedPoint(
            coordinate: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.41),
            weight: 60
        )
        let z = 12
        let tileX = Int(((point.coordinate.longitude + 180) / 360) * pow(2.0, Double(z)))
        let latRad = point.coordinate.latitude * .pi / 180
        let tileY = Int((1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * pow(2.0, Double(z)))

        let light = HeatmapTileRenderer(points: [point], style: .light)
        let dark = HeatmapTileRenderer(points: [point], style: .dark)
        let lightData = loadTile(light, x: tileX, y: tileY, z: z)
        let darkData = loadTile(dark, x: tileX, y: tileY, z: z)
        XCTAssertNotNil(lightData)
        XCTAssertNotNil(darkData)
        XCTAssertNotEqual(lightData, darkData)
    }
}
