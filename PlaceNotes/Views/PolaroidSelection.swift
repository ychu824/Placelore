import Foundation

/// Pure-function helper that selects which journal entries should appear as
/// polaroid decorations on the Tracking page. Kept separate from the SwiftUI
/// view so the selection rules can be unit-tested without UI.
enum PolaroidSelection {
    /// Filters out entries with no photos and returns at most the first two,
    /// preserving the caller's order. Caller is responsible for sorting
    /// (typically `.date` descending via `@Query`).
    static func selectFor(entries: [JournalEntry]) -> [JournalEntry] {
        Array(entries.lazy.filter { !$0.photoAssetIdentifiers.isEmpty }.prefix(2))
    }
}
