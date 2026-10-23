import CoreLocation
import Foundation
import Photos
import os

private let logger = Logger(subsystem: "dev.placelore.app", category: "PhotoLibraryExporter")

/// Copies journal photos from the app's sandbox into the system Photos library.
enum PhotoLibraryExporter {
    struct Item {
        let filename: String
        var creationDate: Date?
        var location: CLLocation?
    }

    struct Summary: Equatable {
        let saved: Int
        let failed: Int
    }

    enum ExportError: LocalizedError {
        case accessDenied
        case accessRestricted
        case nothingToSave
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return String(localized: "Allow Placelore to add photos in Settings → Placelore → Photos.")
            case .accessRestricted:
                return String(localized: "Adding photos to your Photos library is restricted on this device.")
            case .nothingToSave:
                return String(localized: "There are no photos to save.")
            case .saveFailed:
                return String(localized: "The photos couldn't be added to your Photos library.")
            }
        }
    }

    private static let batchSize = 25

    /// Builds export items from journal entries, carrying the entry date and
    /// place coordinate so saved photos land at the right spot in the Photos
    /// timeline and map (the stored JPEGs carry no EXIF of their own).
    /// The visit's place wins over the entry's because correcting a visit's
    /// place only updates the visit. Duplicate filenames keep the first one.
    static func items(from entries: [JournalEntry]) -> [Item] {
        var seen = Set<String>()
        return entries.flatMap { entry -> [Item] in
            let location = (entry.visit?.place ?? entry.place).map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            }
            return entry.photoAssetIdentifiers.compactMap { filename in
                guard seen.insert(filename).inserted else { return nil }
                return Item(filename: filename, creationDate: entry.date, location: location)
            }
        }
    }

    /// Like `items(from:)`, but drops photos whose file is no longer on disk,
    /// so counts shown to the user match what `save` will actually add.
    static func savableItems(from entries: [JournalEntry]) -> [Item] {
        items(from: entries).filter { isOnDisk($0) }
    }

    static func item(for filename: String, in entries: [JournalEntry]) -> Item {
        items(from: entries).first { $0.filename == filename } ?? Item(filename: filename)
    }

    /// Saves the given photos to the Photos library, requesting add-only
    /// access if needed. Files missing from disk and files PhotoKit rejects
    /// count as failed; the rest are still saved. Throws only when nothing
    /// could be saved.
    static func save(_ items: [Item]) async throws -> Summary {
        let present = items.filter { isOnDisk($0) }
        let missingCount = items.count - present.count
        if missingCount > 0 {
            logger.error("Skipping \(missingCount) photo(s) missing from disk")
        }
        guard !present.isEmpty else { throw ExportError.nothingToSave }

        try await requestAccess()

        var saved = 0
        for start in stride(from: 0, to: present.count, by: batchSize) {
            let batch = Array(present[start..<min(start + batchSize, present.count)])
            do {
                try await performCreation(of: batch)
                saved += batch.count
            } catch {
                // A batch is all-or-nothing; retry singly so one bad file
                // doesn't take its neighbours in the batch down with it.
                logger.error("Photos batch failed, retrying singly: \(error.localizedDescription, privacy: .public)")
                for item in batch {
                    do {
                        try await performCreation(of: [item])
                        saved += 1
                    } catch {
                        logger.error("Photos save failed for \(item.filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        guard saved > 0 else { throw ExportError.saveFailed }
        return Summary(saved: saved, failed: items.count - saved)
    }

    private static func isOnDisk(_ item: Item) -> Bool {
        FileManager.default.fileExists(atPath: PhotoStorage.fileURL(for: item.filename).path)
    }

    private static func performCreation(of items: [Item]) async throws {
        let resources = items.map { ($0, PhotoStorage.fileURL(for: $0.filename)) }
        try await PHPhotoLibrary.shared().performChanges {
            for (item, url) in resources {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: url, options: nil)
                if let creationDate = item.creationDate {
                    request.creationDate = creationDate
                }
                if let location = item.location {
                    request.location = location
                }
            }
        }
    }

    private static func requestAccess() async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        switch status {
        case .authorized, .limited:
            return
        case .restricted:
            throw ExportError.accessRestricted
        default:
            throw ExportError.accessDenied
        }
    }
}
