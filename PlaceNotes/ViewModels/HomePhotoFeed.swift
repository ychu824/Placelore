import Foundation
import SwiftData

struct HomePhotoItem: Identifiable, Equatable {
    let id: String
    let filename: String
    let entryID: PersistentIdentifier
    let placeID: PersistentIdentifier?
    let date: Date
}

enum HomePhotoFeed {
    /// Flattens a list of `JournalEntry` into per-photo items, preserving the
    /// input order of entries and the order of `photoAssetIdentifiers` within
    /// each entry. Entries with no photos are skipped.
    static func flatten(_ entries: [JournalEntry]) -> [HomePhotoItem] {
        entries.flatMap { entry -> [HomePhotoItem] in
            entry.photoAssetIdentifiers.map { filename in
                HomePhotoItem(
                    id: filename,
                    filename: filename,
                    entryID: entry.persistentModelID,
                    placeID: entry.place?.persistentModelID,
                    date: entry.date
                )
            }
        }
    }
}
