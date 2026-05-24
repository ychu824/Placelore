import Foundation
import CoreLocation

enum TrajectoryBuilder {
    /// Split a chronologically sorted run of samples wherever the temporal gap
    /// between consecutive samples is **strictly greater than** `maxGapSeconds`.
    /// Without this we would draw a "teleport" line across the gap.
    static func splitIntoSegments(
        _ samples: [RawLocationSample],
        maxGapSeconds: TimeInterval
    ) -> [[RawLocationSample]] {
        guard !samples.isEmpty else { return [] }

        var result: [[RawLocationSample]] = []
        var current: [RawLocationSample] = [samples[0]]

        for i in 1..<samples.count {
            let prev = samples[i - 1]
            let next = samples[i]
            if next.timestamp.timeIntervalSince(prev.timestamp) > maxGapSeconds {
                result.append(current)
                current = [next]
            } else {
                current.append(next)
            }
        }
        result.append(current)
        return result
    }

    /// Douglas–Peucker line simplification. Drops points whose perpendicular
    /// distance from the local approximation line is < `epsilonMeters`.
    /// Uses an equirectangular projection around the input's midpoint — good
    /// enough at the few-km scale a single day's path occupies.
    static func simplify(
        _ points: [TrajectoryPoint],
        epsilonMeters: Double
    ) -> [TrajectoryPoint] {
        guard points.count > 2 else { return points }

        let midLat = (points[0].coordinate.latitude + points[points.count - 1].coordinate.latitude) / 2
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(midLat * .pi / 180)

        func project(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (x: c.longitude * metersPerDegLon, y: c.latitude * metersPerDegLat)
        }

        func perpendicularDistance(
            _ p: CLLocationCoordinate2D,
            from a: CLLocationCoordinate2D,
            to b: CLLocationCoordinate2D
        ) -> Double {
            let pp = project(p), pa = project(a), pb = project(b)
            let dx = pb.x - pa.x
            let dy = pb.y - pa.y
            let lengthSq = dx * dx + dy * dy
            if lengthSq == 0 {
                let ex = pp.x - pa.x, ey = pp.y - pa.y
                return (ex * ex + ey * ey).squareRoot()
            }
            let cross = abs((pp.x - pa.x) * dy - (pp.y - pa.y) * dx)
            return cross / lengthSq.squareRoot()
        }

        func recurse(start: Int, end: Int, into keep: inout [Bool]) {
            guard end > start + 1 else { return }
            var maxDist = 0.0
            var maxIdx = start
            let a = points[start].coordinate
            let b = points[end].coordinate
            for i in (start + 1)..<end {
                let d = perpendicularDistance(points[i].coordinate, from: a, to: b)
                if d > maxDist {
                    maxDist = d
                    maxIdx = i
                }
            }
            if maxDist > epsilonMeters {
                keep[maxIdx] = true
                recurse(start: start, end: maxIdx, into: &keep)
                recurse(start: maxIdx, end: end, into: &keep)
            }
        }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        recurse(start: 0, end: points.count - 1, into: &keep)

        return zip(points, keep).compactMap { $0.1 ? $0.0 : nil }
    }

    /// Drop physically-impossible GPS fixes ("teleports") from a
    /// chronologically-sorted run of samples. A fix is rejected when its
    /// implied speed from the last *kept* sample exceeds
    /// `maxSpeedMetersPerSecond`. Anchoring on the last kept sample — rather
    /// than the immediate predecessor — means a lone outlier is discarded
    /// without also dropping the valid fix that follows it.
    ///
    /// The device's self-reported `horizontalAccuracy` can stay small on a
    /// grossly wrong fix, so the accuracy gate upstream never catches these;
    /// the inter-sample speed is the only reliable signal.
    static func rejectOutliers(
        _ samples: [RawLocationSample],
        maxSpeedMetersPerSecond: Double
    ) -> [RawLocationSample] {
        guard let first = samples.first else { return [] }

        var kept: [RawLocationSample] = [first]
        var anchor = first

        for i in 1..<samples.count {
            let candidate = samples[i]
            let dt = candidate.timestamp.timeIntervalSince(anchor.timestamp)
            let anchorLoc = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
            let candidateLoc = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
            let distance = anchorLoc.distance(from: candidateLoc)
            // dt <= 0 means duplicate/zero-interval timestamps; a co-located
            // fix is fine, but any spatial jump in zero time is a teleport.
            let impliedSpeed = dt > 0 ? distance / dt : (distance == 0 ? 0 : .infinity)
            if impliedSpeed <= maxSpeedMetersPerSecond {
                kept.append(candidate)
                anchor = candidate
            }
        }
        return kept
    }

    static func computeStats(
        segments: [TrajectorySegment],
        rawSampleCount: Int,
        placeCount: Int
    ) -> TrajectoryStats {
        var totalDistance: Double = 0
        var drawnPointCount = 0

        for segment in segments {
            drawnPointCount += segment.points.count
            guard segment.points.count > 1 else { continue }
            for i in 1..<segment.points.count {
                let a = segment.points[i - 1].coordinate
                let b = segment.points[i].coordinate
                let aLoc = CLLocation(latitude: a.latitude, longitude: a.longitude)
                let bLoc = CLLocation(latitude: b.latitude, longitude: b.longitude)
                totalDistance += aLoc.distance(from: bLoc)
            }
        }

        return TrajectoryStats(
            totalDistanceMeters: totalDistance,
            rawSampleCount: rawSampleCount,
            drawnPointCount: drawnPointCount,
            segmentCount: segments.count,
            placeCount: placeCount
        )
    }

    static func build(
        samples: [RawLocationSample],
        day: Date,
        epsilonMeters: Double = 5,
        maxGapSeconds: TimeInterval = 600,
        maxSpeedMetersPerSecond: Double = 50
    ) -> [TrajectorySegment] {
        let dayStart = Calendar.current.startOfDay(for: day)
        let cleaned = rejectOutliers(samples, maxSpeedMetersPerSecond: maxSpeedMetersPerSecond)
        let raw = splitIntoSegments(cleaned, maxGapSeconds: maxGapSeconds)

        return raw.compactMap { rawSegment in
            let points = convertToPoints(rawSegment, dayStart: dayStart)
            let simplified = epsilonMeters > 0 ? simplify(points, epsilonMeters: epsilonMeters) : points
            guard simplified.count >= 2 else { return nil }
            return TrajectorySegment(points: simplified)
        }
    }

    private static func convertToPoints(
        _ samples: [RawLocationSample],
        dayStart: Date
    ) -> [TrajectoryPoint] {
        // Use the calendar to compute day length so DST transitions (23h or 25h
        // local days) produce a normalizedTimeOfDay that doesn't drift past 1.
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let dayLength = nextDay.timeIntervalSince(dayStart)

        return samples.map { s in
            let raw = s.timestamp.timeIntervalSince(dayStart) / dayLength
            let normalized = min(1.0, max(0.0, raw))
            // CoreLocation reports speed = -1 when unknown. v1 doesn't render
            // speed, so coerce to 0; if the v2 .speed color mode lands, this
            // should be revisited (likely promote speedMetersPerSecond to optional).
            let speed = max(0, s.speed)
            return TrajectoryPoint(
                coordinate: CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude),
                timestamp: s.timestamp,
                normalizedTimeOfDay: normalized,
                speedMetersPerSecond: speed
            )
        }
    }
}
