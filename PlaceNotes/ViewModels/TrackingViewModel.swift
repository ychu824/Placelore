import Foundation
import Combine

@MainActor
final class TrackingViewModel: ObservableObject {
    let trackingManager: TrackingManager

    @Published var statusText: String = ""
    @Published var pauseTimeRemainingText: String?

    private var cancellables = Set<AnyCancellable>()
    private var displayTimer: Timer?

    init(trackingManager: TrackingManager) {
        self.trackingManager = trackingManager

        trackingManager.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateStatusText(state)
            }
            .store(in: &cancellables)

        updateStatusText(trackingManager.state)
    }

    deinit {
        displayTimer?.invalidate()
    }

    func enable() {
        trackingManager.enableTracking()
    }

    func disable() {
        trackingManager.disableTracking()
    }

    func pause(for duration: PauseDuration) {
        trackingManager.pauseTracking(for: duration)
    }

    func resume() {
        trackingManager.resumeTracking()
    }

    // MARK: - Private

    /// The 1 Hz countdown only needs to run while paused; running it
    /// permanently would publish view invalidations every second for the
    /// app's whole lifetime.
    private func setDisplayTimerRunning(_ running: Bool) {
        if running {
            guard displayTimer == nil else { return }
            displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatusText(self?.trackingManager.state ?? .default)
                }
            }
        } else {
            displayTimer?.invalidate()
            displayTimer = nil
        }
    }

    private func updateStatusText(_ state: TrackingState) {
        let newStatus: String
        let newRemaining: String?
        switch state.status {
        case .active:
            newStatus = String(localized: "Tracking Active")
            newRemaining = nil
        case .disabled:
            newStatus = String(localized: "Tracking Disabled")
            newRemaining = nil
        case .paused:
            if let remaining = state.pauseTimeRemaining, remaining > 0 {
                newStatus = String(localized: "Tracking Paused")
                newRemaining = formatTimeRemaining(remaining)
            } else {
                newStatus = String(localized: "Tracking Active")
                newRemaining = nil
            }
        }
        if statusText != newStatus { statusText = newStatus }
        if pauseTimeRemainingText != newRemaining { pauseTimeRemainingText = newRemaining }
        setDisplayTimerRunning(newRemaining != nil)
    }

    private func formatTimeRemaining(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "Resumes in %dh %02dm", hours, minutes)
        } else {
            return String(format: "Resumes in %dm %02ds", minutes, seconds)
        }
    }
}
