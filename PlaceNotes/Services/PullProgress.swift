import CoreGraphics

enum PullProgress {

    /// Maps a non-negative pull distance to a 0...1 progress value.
    /// Returns 0 for non-positive thresholds or negative distances.
    static func progress(distance: CGFloat, threshold: CGFloat) -> Double {
        guard threshold > 0 else { return 0 }
        let clampedDistance = max(0, distance)
        return min(1.0, Double(clampedDistance / threshold))
    }

    /// True only on the rising edge from below 1.0 to exactly 1.0 (or above).
    static func didCrossThreshold(old: Double, new: Double) -> Bool {
        old < 1.0 && new >= 1.0
    }
}
