import Foundation
import Combine
import ActivityKit
import os

private let logger = Logger(subsystem: "dev.placelore.app", category: "LiveActivityManager")

/// Drives the capture Live Activity that lives in the Dynamic Island / Lock
/// Screen. It mirrors tracking state: a single activity is kept alive while
/// tracking is `.active` and ended otherwise.
///
/// Note: iOS only ever surfaces one app's Live Activity in the Dynamic Island at
/// a time, so while another app (e.g. an airline boarding pass) is occupying the
/// island ours yields to it and is shown on the Lock Screen instead. The in-app
/// pull/tap-to-capture affordance in `HomeView` remains the always-available
/// fallback.
///
/// All tracking-state callbacks are delivered on the main run loop via the
/// Combine subscription below, so ActivityKit mutations stay on the main thread.
final class LiveActivityManager {

    private var cancellable: AnyCancellable?

    func observe(_ trackingManager: TrackingManager) {
        cancellable = trackingManager.$state
            .map(\.status)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.sync(status: status)
            }
        sync(status: trackingManager.state.status)
    }

    /// Update the dwell place shown in the island without restarting the activity.
    func updatePlace(_ placeName: String?) {
        guard let activity = Activity<CaptureActivityAttributes>.activities.first else { return }
        Task {
            let state = CaptureActivityAttributes.ContentState(placeName: placeName)
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func sync(status: TrackingStatus) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        switch status {
        case .active:
            startIfNeeded()
        case .paused, .disabled:
            endAll()
        }
    }

    private func startIfNeeded() {
        guard Activity<CaptureActivityAttributes>.activities.isEmpty else { return }
        let attributes = CaptureActivityAttributes(startedAt: Date())
        let state = CaptureActivityAttributes.ContentState(placeName: nil)
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            logger.info("Capture Live Activity started")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func endAll() {
        let active = Activity<CaptureActivityAttributes>.activities
        guard !active.isEmpty else { return }
        Task {
            for activity in active {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            logger.info("Capture Live Activity ended")
        }
    }
}
