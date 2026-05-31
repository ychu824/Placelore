import ActivityKit
import Foundation

/// Shared between the app (which starts/updates/ends the activity) and the
/// `PlaceCaptureWidget` extension (which renders it in the Dynamic Island and on
/// the Lock Screen). This file is intentionally compiled into both targets.
struct CaptureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Name of the place the user is currently dwelling at, if resolved.
        var placeName: String?
        /// Emoji for the resolved place (custom or category default).
        var placeEmoji: String? = nil
        /// When the current visit began — drives a live "time here" label.
        var arrivalDate: Date? = nil
        /// Visits to this place before the current one (mirrors the home card).
        var priorVisitCount: Int = 0
    }

    /// When the current tracking session began — used for a subtle "since" label.
    var startedAt: Date
}

extension CaptureActivityAttributes {
    /// Deep link opened when the Live Activity (or any of its regions) is tapped.
    static let captureURL = URL(string: "placelore://capture")!
}

extension CaptureActivityAttributes.ContentState {
    /// Emoji + place name, falling back to the app name before a place resolves.
    /// Mirrors the home "You're at" card's heading.
    var title: String {
        guard let placeName, !placeName.isEmpty else { return "Placelore" }
        guard let placeEmoji, !placeEmoji.isEmpty else { return placeName }
        return "\(placeEmoji) \(placeName)"
    }

    /// Prior-visit subtitle matching the home card's wording.
    var priorVisitsText: String {
        switch max(0, priorVisitCount) {
        case 0: return "First visit here"
        case 1: return "1 prior visit"
        case let count: return "\(count) prior visits"
        }
    }
}
