import Foundation
import CoreLocation
import Combine
import SwiftData
import UIKit
import os

private let logger = Logger(subsystem: "dev.placelore.app", category: "QuickCaptureViewModel")

@MainActor
final class QuickCaptureViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case acquiringLocation
        case savingPhoto
        case resolvingPlace
        case manualPickNeeded
        case done(ToastPayload)
        case error(String)
    }

    struct ToastPayload: Equatable {
        enum Kind: Equatable { case newVisit, merged }
        let kind: Kind
        let placeName: String
        let visitID: UUID
        let journalEntryID: UUID
    }

    @Published private(set) var state: State = .idle
    @Published var showCamera: Bool = false
    @Published private(set) var pendingPhotoAssetId: String?

    var isWorkingInBackground: Bool {
        switch state {
        case .savingPhoto, .resolvingPlace: return true
        default: return false
        }
    }

    /// Time budget for the background warm-up fetch kicked off when the camera opens.
    /// Most users compose for >5s; keep this generous so a warm-up fix usually lands
    /// before the shutter, but the shutter-time retry is the real safety net.
    static let warmupTimeout: TimeInterval = 15

    /// Time budget for the retry fetch issued at shutter time when warm-up failed.
    /// Tuned to be long enough for a cold GPS fix but short enough that the user
    /// doesn't see the saving spinner for an eternity.
    static let shutterTimeout: TimeInterval = 10

    private let oneShot: LocationOneShotProviding
    private let context: ModelContext
    private weak var locationManager: LocationManager?
    private var pendingLiveFix: CLLocation?
    private var locationFetchTask: Task<Void, Never>?

    init(
        oneShot: LocationOneShotProviding,
        context: ModelContext,
        locationManager: LocationManager? = nil
    ) {
        self.oneShot = oneShot
        self.context = context
        self.locationManager = locationManager
    }

    // MARK: - Flow

    func beginCapture() {
        guard state == .idle else { return }
        state = .acquiringLocation
        showCamera = true
        pendingLiveFix = nil
        locationFetchTask?.cancel()
        oneShot.cancel()
        locationFetchTask = Task { [weak self] in
            guard let self else { return }
            let loc = await self.oneShot.fetchOnce(timeout: Self.warmupTimeout)
            if Task.isCancelled { return }
            await MainActor.run { self.pendingLiveFix = loc }
        }
    }

    func photoCaptured(image: UIImage, exifLocation: CLLocation?) {
        state = .savingPhoto
        Task { [weak self] in
            guard let self else { return }
            guard let filename = PhotoStorage.saveImage(image) else {
                logger.error("PhotoStorage.saveImage returned nil")
                await MainActor.run { self.state = .error("Couldn't save photo to disk.") }
                return
            }
            await self.continueAfterPhoto(photoAssetId: filename, exifLocation: exifLocation)
        }
    }

    func cancelCapture() {
        locationFetchTask?.cancel()
        oneShot.cancel()
        pendingLiveFix = nil
        pendingPhotoAssetId = nil
        showCamera = false
        state = .idle
    }

    func manualPlaceSelected(_ place: Place, photoAssetId: String) {
        state = .resolvingPlace
        Task { [weak self] in
            guard let self else { return }
            let result = await QuickCaptureService.logCapture(
                coordinate: CLLocation(latitude: place.latitude, longitude: place.longitude),
                photoAssetId: photoAssetId,
                in: self.context
            )
            await MainActor.run { self.state = .done(self.toast(from: result)) }
        }
    }

    func undoNewVisit(_ payload: ToastPayload) {
        let visitID = payload.visitID
        let visitDesc = FetchDescriptor<Visit>(predicate: #Predicate { $0.id == visitID })
        if let visit = (try? context.fetch(visitDesc))?.first {
            JournalEntryDeletion.cleanupPhotos(for: visit)
            context.delete(visit)
        }
        try? context.save()
        state = .idle
    }

    func splitFromMerge(_ payload: ToastPayload) {
        let journalEntryID = payload.journalEntryID
        let entryDesc = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == journalEntryID })
        guard let entry = (try? context.fetch(entryDesc))?.first, let place = entry.place else {
            state = .idle
            return
        }
        let now = Date()
        let visit = Visit(
            arrivalDate: now,
            departureDate: now.addingTimeInterval(QuickCaptureService.quickVisitDuration),
            place: place
        )
        visit.confidence = .high
        visit.isQuickCapture = true
        context.insert(visit)
        entry.visit = visit
        try? context.save()
        state = .idle
    }

    // MARK: - Private

    private func continueAfterPhoto(photoAssetId: String, exifLocation: CLLocation?) async {
        if pendingLiveFix == nil {
            logger.info("Warm-up fix missing at shutter — retrying with \(Self.shutterTimeout)s budget")
            let retry = await oneShot.fetchOnce(timeout: Self.shutterTimeout)
            if let retry { pendingLiveFix = retry }
        }
        let cachedFix = locationManager?.lastFix
        let coord = QuickCaptureService.resolveCoordinate(
            liveFix: pendingLiveFix,
            exifLocation: exifLocation,
            cachedFix: cachedFix
        )
        guard let coord else {
            logger.info("No coordinate available — falling back to manual picker")
            await MainActor.run {
                self.pendingPhotoAssetId = photoAssetId
                self.state = .manualPickNeeded
            }
            return
        }
        await MainActor.run { self.state = .resolvingPlace }
        let result = await QuickCaptureService.logCapture(
            coordinate: coord,
            photoAssetId: photoAssetId,
            in: context
        )
        await MainActor.run { self.state = .done(self.toast(from: result)) }
    }

    private func toast(from result: QuickCaptureResult) -> ToastPayload {
        switch result {
        case .newVisit(let vid, let name, let eid):
            return ToastPayload(kind: .newVisit, placeName: name, visitID: vid, journalEntryID: eid)
        case .merged(let vid, let name, let eid):
            return ToastPayload(kind: .merged, placeName: name, visitID: vid, journalEntryID: eid)
        }
    }

}
