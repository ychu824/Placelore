import CoreLocation
import Foundation

struct WeightedPoint: Equatable {
    let coordinate: CLLocationCoordinate2D
    let weight: Double

    static func == (lhs: WeightedPoint, rhs: WeightedPoint) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.weight == rhs.weight
    }
}

enum KDEKernel {
    /// Sum of weighted gaussians (equirectangular projection — fine for
    /// the few-km radius a single tile covers).
    static func evaluate(
        at coord: CLLocationCoordinate2D,
        points: [WeightedPoint],
        bandwidthMeters: Double
    ) -> Double {
        guard !points.isEmpty, bandwidthMeters > 0 else { return 0 }
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(coord.latitude * .pi / 180)
        let twoSigmaSq = 2 * bandwidthMeters * bandwidthMeters
        var sum = 0.0
        for p in points {
            let dy = (p.coordinate.latitude - coord.latitude) * metersPerDegLat
            let dx = (p.coordinate.longitude - coord.longitude) * metersPerDegLon
            let distSq = dx * dx + dy * dy
            sum += p.weight * exp(-distSq / twoSigmaSq)
        }
        return sum
    }
}
