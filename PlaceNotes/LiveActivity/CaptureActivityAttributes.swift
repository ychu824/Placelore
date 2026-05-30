import ActivityKit
import Foundation

/// Shared between the app (which starts/updates/ends the activity) and the
/// `PlaceCaptureWidget` extension (which renders it in the Dynamic Island and on
/// the Lock Screen). This file is intentionally compiled into both targets.
struct CaptureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Name of the place the user is currently dwelling at, if resolved.
        var placeName: String?
    }

    /// When the current tracking session began — used for a subtle "since" label.
    var startedAt: Date
}

extension CaptureActivityAttributes {
    /// Deep link opened when the Live Activity (or any of its regions) is tapped.
    static let captureURL = URL(string: "placelore://capture")!
}
