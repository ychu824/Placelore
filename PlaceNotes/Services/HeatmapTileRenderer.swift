import MapKit
import UIKit
import CoreGraphics

final class HeatmapTileRenderer: MKTileOverlay {
    private let points: [WeightedPoint]
    private let palette: HeatmapPalette
    private let maxValue: Double            // cap used to normalize intensities

    init(points: [WeightedPoint], style: UIUserInterfaceStyle) {
        self.points = points
        self.palette = HeatmapPalette.forStyle(style)
        self.maxValue = Self.normalizationCap(for: points)
        super.init(urlTemplate: nil)
        self.canReplaceMapContent = false
        self.tileSize = CGSize(width: 256, height: 256)
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        URL(string: "about:blank")!     // unused; loadTile is overridden
    }

    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        guard !points.isEmpty else {
            result(nil, nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [points, palette, maxValue] in
            let data = Self.rasterize(path: path, points: points, palette: palette, maxValue: maxValue)
            result(data, nil)
        }
    }

    // MARK: - Rasterization

    private static func rasterize(
        path: MKTileOverlayPath,
        points: [WeightedPoint],
        palette: HeatmapPalette,
        maxValue: Double
    ) -> Data? {
        let tilePixels = 64                     // downsampled grid, upsampled by ImageIO
        let z = path.z
        let scale = pow(2.0, Double(z))
        let west = Double(path.x) / scale * 360 - 180
        let east = Double(path.x + 1) / scale * 360 - 180
        let northRad = atan(sinh(.pi * (1 - 2 * Double(path.y) / scale)))
        let southRad = atan(sinh(.pi * (1 - 2 * Double(path.y + 1) / scale)))
        let north = northRad * 180 / .pi
        let south = southRad * 180 / .pi

        if !Self.tileIntersectsAnyPoint(points: points, west: west, east: east, south: south, north: north, paddingDegrees: 0.05) {
            return nil
        }

        let bandwidth = Self.bandwidthMeters(forZoom: z)
        var pixels = [UInt8](repeating: 0, count: tilePixels * tilePixels * 4)

        for py in 0..<tilePixels {
            let lat = north + (south - north) * (Double(py) + 0.5) / Double(tilePixels)
            for px in 0..<tilePixels {
                let lon = west + (east - west) * (Double(px) + 0.5) / Double(tilePixels)
                let intensity = KDEKernel.evaluate(
                    at: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    points: points,
                    bandwidthMeters: bandwidth
                )
                let normalized = maxValue > 0 ? min(intensity / maxValue, 1) : 0
                let rgba = palette.rgba(for: normalized)
                let i = (py * tilePixels + px) * 4
                pixels[i] = rgba.r
                pixels[i + 1] = rgba.g
                pixels[i + 2] = rgba.b
                pixels[i + 3] = rgba.a
            }
        }
        return makePNG(pixels: pixels, width: tilePixels, height: tilePixels)
    }

    private static func makePNG(pixels: [UInt8], width: Int, height: Int) -> Data? {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info: UInt32 = CGImageAlphaInfo.last.rawValue
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        guard let cg = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: info),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cg).pngData()
    }

    private static func tileIntersectsAnyPoint(
        points: [WeightedPoint],
        west: Double, east: Double,
        south: Double, north: Double,
        paddingDegrees: Double
    ) -> Bool {
        for p in points {
            let lat = p.coordinate.latitude
            let lon = p.coordinate.longitude
            if lat >= south - paddingDegrees && lat <= north + paddingDegrees &&
               lon >= west - paddingDegrees && lon <= east + paddingDegrees {
                return true
            }
        }
        return false
    }

    private static func bandwidthMeters(forZoom z: Int) -> Double {
        let base = 150.0
        let referenceZoom = 16.0
        // Bandwidth doubles per zoom level out so hotspots remain visually consistent.
        return base * pow(2.0, referenceZoom - Double(z))
    }

    /// 95th-percentile weight. Stable across tiles so the same hot spot reads
    /// the same color regardless of which tile renders it.
    private static func normalizationCap(for points: [WeightedPoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        let sorted = points.map(\.weight).sorted()
        let idx = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95)))
        let p95 = sorted[idx]
        return max(p95, 0.0001)  // never zero (guards against divide-by-zero downstream)
    }
}
