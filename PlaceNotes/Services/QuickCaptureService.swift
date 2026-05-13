import Foundation
import CoreLocation
import SwiftData
import os

private let logger = Logger(subsystem: "dev.placelore.app", category: "QuickCaptureService")

enum QuickCaptureResult {
    case newVisit(visitID: UUID, placeName: String, journalEntryID: UUID)
    case merged(intoVisitID: UUID, placeName: String, journalEntryID: UUID)
}

enum QuickCaptureError: Error {
    case photoSaveFailed
}

enum QuickCaptureService {

    /// Max accuracy (meters) to trust a live GPS fix. Beyond this, fall through to EXIF.
    /// Matches the 50m nearest-place radius in PlaceResolver — if accuracy exceeds the
    /// matching radius, a "nearest" lookup could mis-attribute across neighbors.
    static let liveFixAccuracyThreshold: CLLocationDistance = 50

    /// Max age (seconds) for a cached `LocationManager.userLocation` fallback
    /// to count as "recent enough" to attribute a photo to.
    static let cachedFixMaxAge: TimeInterval = 120

    /// Resolves the coordinate for a quick capture in priority order:
    /// 1. live fix if accuracy ≤ 50m
    /// 2. EXIF location from the photo metadata
    /// 3. recent passive-tracking fix (≤ 120s old, ≤ 50m accuracy)
    /// 4. nil (caller opens ManualPlacePickerView)
    static func resolveCoordinate(
        liveFix: CLLocation?,
        exifLocation: CLLocation?,
        cachedFix: CLLocation? = nil,
        now: Date = Date()
    ) -> CLLocation? {
        if let live = liveFix,
           live.horizontalAccuracy >= 0,
           live.horizontalAccuracy <= liveFixAccuracyThreshold {
            return live
        }
        if let exif = exifLocation {
            return exif
        }
        if let cached = cachedFix,
           cached.horizontalAccuracy >= 0,
           cached.horizontalAccuracy <= liveFixAccuracyThreshold,
           now.timeIntervalSince(cached.timestamp) <= cachedFixMaxAge {
            return cached
        }
        return nil
    }
}

extension QuickCaptureService {

    static let mergeWindow: TimeInterval = 30 * 60

    enum MergeDecision: Equatable {
        case mergeWith(visitID: UUID)
        case createNew
    }

    static func mergeDecision(for place: Place, now: Date) -> MergeDecision {
        let cutoff = now.addingTimeInterval(-mergeWindow)
        let candidate = place.visits
            .filter { visit in
                if visit.departureDate == nil { return true }
                return (visit.departureDate ?? .distantPast) > cutoff
            }
            .sorted { $0.arrivalDate > $1.arrivalDate }
            .first
        if let c = candidate {
            return .mergeWith(visitID: c.id)
        }
        return .createNew
    }
}

extension QuickCaptureService {

    static let quickVisitDuration: TimeInterval = 60

    @MainActor
    static func logCapture(
        coordinate: CLLocation,
        photoAssetId: String,
        now: Date = Date(),
        in context: ModelContext
    ) async -> QuickCaptureResult {
        let (place, _) = await PlaceResolver.findOrCreate(
            latitude: coordinate.coordinate.latitude,
            longitude: coordinate.coordinate.longitude,
            in: context
        )

        let entry = JournalEntry(date: now, photoAssetIdentifiers: [photoAssetId])
        entry.place = place
        context.insert(entry)

        switch mergeDecision(for: place, now: now) {
        case .mergeWith(let visitID):
            entry.visit = place.visits.first { $0.id == visitID }
            try? context.save()
            return .merged(intoVisitID: visitID, placeName: place.displayName, journalEntryID: entry.id)

        case .createNew:
            let visit = Visit(
                arrivalDate: now,
                departureDate: now.addingTimeInterval(quickVisitDuration),
                place: place
            )
            visit.confidence = .high
            visit.isQuickCapture = true
            context.insert(visit)
            entry.visit = visit
            try? context.save()
            return .newVisit(visitID: visit.id, placeName: place.displayName, journalEntryID: entry.id)
        }
    }
}
