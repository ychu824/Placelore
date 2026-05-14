import Foundation
import Combine
import CoreLocation
import os

private let logger = Logger(subsystem: "dev.placelore.app", category: "TrackingManager")

final class TrackingManager: ObservableObject {
    private let locationManager: LocationManager
    private let settings: AppSettings
    private var pauseTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    @Published var state: TrackingState

    /// True when the most recent enable/resume attempt was blocked because the
    /// user has denied or restricted location access. UI can surface this to
    /// guide the user to Settings.
    @Published var isPermissionDenied: Bool = false

    /// True while the user has requested tracking but the system authorization
    /// prompt is still in flight (status == .notDetermined). When auth flips
    /// to authorized we promote to `.active`; if it flips to denied we abandon.
    private var pendingEnable: Bool = false

    init(locationManager: LocationManager, settings: AppSettings = .shared) {
        self.locationManager = locationManager
        self.settings = settings
        self.state = settings.trackingState
        logger.info("TrackingManager initialized, state: \(self.state.status.rawValue), auth: \(locationManager.authorizationStatus.rawValue)")

        observeAuthorizationChanges()
        checkPauseExpiry()
    }

    func enableTracking() {
        logger.notice(">>> Enable tracking requested <<<")
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            applyEnabled()
        case .notDetermined:
            pendingEnable = true
            locationManager.requestAuthorization()
            logger.info("Auth not determined — awaiting user decision")
        case .denied, .restricted:
            isPermissionDenied = true
            logger.warning("Cannot enable tracking — permission \(self.locationManager.authorizationStatus.rawValue)")
        @unknown default:
            isPermissionDenied = true
            logger.warning("Cannot enable tracking — unknown authorization value")
        }
    }

    func disableTracking() {
        logger.notice(">>> Disable tracking requested <<<")
        pendingEnable = false
        state.status = .disabled
        state.pauseResumeDate = nil
        locationManager.stopMonitoring()
        pauseTimer?.invalidate()
        persist()
        logger.notice("Tracking disabled")
    }

    func pauseTracking(for duration: PauseDuration) {
        logger.notice(">>> Pause tracking for \(duration.interval, format: .fixed(precision: 0))s <<<")
        pendingEnable = false
        state.status = .paused
        state.pauseResumeDate = Date().addingTimeInterval(duration.interval)
        locationManager.stopMonitoring()
        schedulePauseResume(after: duration.interval)
        persist()
    }

    func resumeTracking() {
        logger.notice(">>> Resume tracking <<<")
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            applyEnabled()
        case .notDetermined:
            pendingEnable = true
            locationManager.requestAuthorization()
        case .denied, .restricted:
            isPermissionDenied = true
            state.status = .disabled
            state.pauseResumeDate = nil
            pauseTimer?.invalidate()
            persist()
            logger.warning("Resume blocked — permission denied; state reset to disabled")
        @unknown default:
            isPermissionDenied = true
            state.status = .disabled
            state.pauseResumeDate = nil
            pauseTimer?.invalidate()
            persist()
        }
    }

    // MARK: - Private

    private func applyEnabled() {
        pendingEnable = false
        isPermissionDenied = false
        state.status = .active
        state.pauseResumeDate = nil
        pauseTimer?.invalidate()
        locationManager.startMonitoring()
        persist()
        logger.notice("Tracking enabled and monitoring started")
    }

    private var isAuthorized: Bool {
        let status = locationManager.authorizationStatus
        return status == .authorizedAlways || status == .authorizedWhenInUse
    }

    private func observeAuthorizationChanges() {
        locationManager.$authorizationStatus
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handleAuthorizationChange(status)
            }
            .store(in: &cancellables)
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        logger.notice("TrackingManager observed auth change: \(status.rawValue)")
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            isPermissionDenied = false
            if pendingEnable || state.status == .active {
                applyEnabled()
            }
        case .denied, .restricted:
            isPermissionDenied = true
            pendingEnable = false
            if state.status != .disabled {
                state.status = .disabled
                state.pauseResumeDate = nil
                locationManager.stopMonitoring()
                pauseTimer?.invalidate()
                persist()
                logger.warning("Tracking demoted to disabled — authorization revoked")
            }
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    private func schedulePauseResume(after interval: TimeInterval) {
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            logger.info("Pause timer fired — auto-resuming")
            self?.resumeTracking()
        }
    }

    private func checkPauseExpiry() {
        if state.status == .paused, let resumeDate = state.pauseResumeDate {
            if Date() >= resumeDate {
                logger.info("Pause expired during app launch — resuming")
                resumeTracking()
            } else {
                let remaining = resumeDate.timeIntervalSince(Date())
                logger.info("Pause still active — \(Int(remaining))s remaining")
                schedulePauseResume(after: remaining)
                locationManager.stopMonitoring()
            }
        } else if state.status == .active {
            if isAuthorized {
                logger.info("State is active on launch — starting monitoring")
                locationManager.startMonitoring()
            } else if locationManager.authorizationStatus == .notDetermined {
                logger.info("State is active on launch but auth not determined — awaiting prompt")
                pendingEnable = true
                locationManager.requestAuthorization()
            } else {
                logger.warning("State is active on launch but auth denied/restricted — demoting to disabled")
                isPermissionDenied = true
                state.status = .disabled
                state.pauseResumeDate = nil
                persist()
            }
        } else {
            logger.info("State is disabled on launch — not starting monitoring")
        }
    }

    private func persist() {
        settings.trackingState = state
    }
}
