import Foundation

/// Tracks photo edits in the journal entry editor so files on disk are only
/// deleted once the outcome is known: photos the user removes from a saved
/// entry must survive a Cancel, while photos added and then abandoned must
/// not be left orphaned in JournalPhotos.
struct JournalPhotoEditSession {
    private(set) var filenames: [String]
    private let original: Set<String>
    private var added: Set<String> = []

    init(original: [String] = []) {
        self.filenames = original
        self.original = Set(original)
    }

    mutating func add(_ filename: String) {
        filenames.append(filename)
        added.insert(filename)
    }

    /// Returns files that can be deleted right away: only photos added in
    /// this session, since nothing persisted references them yet.
    mutating func remove(_ filename: String) -> [String] {
        filenames.removeAll { $0 == filename }
        guard added.remove(filename) != nil else { return [] }
        return [filename]
    }

    /// Files to delete after the entry is saved with `filenames`.
    var filesToDeleteOnSave: [String] {
        Array(original.subtracting(filenames))
    }

    /// Files to delete when the edit is abandoned.
    var filesToDeleteOnDiscard: [String] {
        Array(added)
    }
}
