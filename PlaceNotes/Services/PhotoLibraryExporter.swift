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

    enum ExportError: LocalizedError {
        case accessDenied
        case nothingToSave

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return String(localized: "Allow Placelore to add photos in Settings → Placelore → Photos.")
            case .nothingToSave:
                return String(localized: "There are no photos to save.")
            }
        }
    }

    /// Keeps each Photos change transaction small so one bad file doesn't
    /// roll back an entire library-wide export.
    private static let batchSize = 25

    /// Builds export items from journal entries, carrying the entry date and
    /// place coordinate so saved photos land at the right spot in the Photos
    /// timeline and map (the stored JPEGs carry no EXIF of their own).
    /// Duplicate filenames are dropped, keeping the first occurrence.
    static func items(from entries: [JournalEntry]) -> [Item] {
        var seen = Set<String>()
        return entries.flatMap { entry -> [Item] in
            let location = (entry.place ?? entry.visit?.place).map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
            return entry.photoAssetIdentifiers.compactMap { filename in
                guard seen.insert(filename).inserted else { return nil }
                return Item(filename: filename, creationDate: entry.date, location: location)
            }
        }
    }

    /// Metadata for a single photo, falling back to a bare item when no entry
    /// in `entries` references `filename`.
    static func item(for filename: String, in entries: [JournalEntry]) -> Item {
        items(from: entries).first { $0.filename == filename } ?? Item(filename: filename)
    }

    /// Saves the given photos to the Photos library, requesting add-only
    /// access if needed. Returns the number of photos saved. Files missing
    /// from disk are skipped.
    @discardableResult
    static func save(_ items: [Item]) async throws -> Int {
        let urls = items.compactMap { item -> (Item, URL)? in
            let url = PhotoStorage.fileURL(for: item.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                logger.error("Skipping missing photo file \(item.filename, privacy: .public)")
                return nil
            }
            return (item, url)
        }
        guard !urls.isEmpty else { throw ExportError.nothingToSave }

        try await requestAccess()

        var savedCount = 0
        for start in stride(from: 0, to: urls.count, by: batchSize) {
            let batch = Array(urls[start..<min(start + batchSize, urls.count)])
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for (item, url) in batch {
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
            } catch {
                logger.error("Photos save failed after \(savedCount) of \(urls.count): \(error.localizedDescription, privacy: .public)")
                throw error
            }
            savedCount += batch.count
        }
        return savedCount
    }

    private static func requestAccess() async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status: PHAuthorizationStatus
        if current == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            status = current
        }
        switch status {
        case .authorized, .limited:
            return
        default:
            throw ExportError.accessDenied
        }
    }
}
