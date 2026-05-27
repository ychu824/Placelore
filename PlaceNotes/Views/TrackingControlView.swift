import SwiftUI
import SwiftData
import UIKit

struct TrackingControlView: View {
    @EnvironmentObject var trackingViewModel: TrackingViewModel
    @EnvironmentObject var quickCapture: QuickCaptureViewModel

    @Query(
        sort: \JournalEntry.date,
        order: .reverse
    )
    private var recentJournalEntries: [JournalEntry]

    @State private var showTrackingSheet = false
    @State private var showCameraPermissionAlert = false
    @State private var showTrackingOffAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                pullDownHint
                    .padding(.top, 4)

                trackingChip

                CurrentlyAtCard()

                Spacer()

                PolaroidDecorationBand(entries: Array(recentJournalEntries.prefix(20)))

                PhotographicShutterButton(isBusy: isBusy) {
                    logThisPlace()
                }

                Text("Tap or pull down to log this place")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard value.translation.height > 80,
                              value.translation.height > abs(value.translation.width) else { return }
                        logThisPlace()
                    }
            )
            .navigationTitle("Placelore")
            .sheet(isPresented: $showTrackingSheet) { trackingSheet }
            .alert("Camera access needed", isPresented: $showCameraPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enable Camera access in Settings → Placelore to capture photos.")
            }
            .alert("Location access needed", isPresented: Binding(
                get: { trackingViewModel.trackingManager.isPermissionDenied },
                set: { newValue in
                    if !newValue {
                        trackingViewModel.trackingManager.isPermissionDenied = false
                    }
                }
            )) {
                Button("Open Settings") {
                    trackingViewModel.trackingManager.isPermissionDenied = false
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {
                    trackingViewModel.trackingManager.isPermissionDenied = false
                }
            } message: {
                Text("Placelore can't track your location until you allow access in Settings → Placelore → Location.")
            }
            .alert("Tracking is off", isPresented: $showTrackingOffAlert) {
                Button("Turn On Tracking") {
                    switch trackingViewModel.trackingManager.state.status {
                    case .paused: trackingViewModel.resume()
                    case .disabled: trackingViewModel.enable()
                    case .active: break
                    }
                    attemptCapture()
                }
                Button("Log Anyway", role: .cancel) {
                    attemptCapture()
                }
            } message: {
                Text("Your location won't be tracked precisely. Turn tracking on for accurate place logging.")
            }
            .animation(
                .easeInOut(duration: 0.3),
                value: recentJournalEntries.prefix(2).map(\.id)
            )
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var trackingChip: some View {
        Button { showTrackingSheet = true } label: {
            HStack(spacing: 6) {
                Image(systemName: chipIcon).foregroundStyle(chipColor)
                Text(trackingViewModel.statusText).font(.footnote.weight(.medium))
                if let remaining = trackingViewModel.pauseTimeRemainingText {
                    Text("·").foregroundStyle(.secondary)
                    Text(remaining).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var isBusy: Bool {
        switch quickCapture.state {
        case .idle: return false
        default: return true
        }
    }

    private var isTrackingActive: Bool {
        trackingViewModel.trackingManager.state.status == .active
    }

    private func logThisPlace() {
        if isTrackingActive {
            attemptCapture()
        } else {
            showTrackingOffAlert = true
        }
    }

    @ViewBuilder
    private var pullDownHint: some View {
        VStack(spacing: 2) {
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 24, weight: .semibold))
            Text("Pull down for camera")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Pull down to open the camera")
    }

    private func attemptCapture() {
        Task {
            if await CameraPickerView.requestCameraPermission() {
                quickCapture.beginCapture()
            } else {
                showCameraPermissionAlert = true
            }
        }
    }

    @ViewBuilder
    private var trackingSheet: some View {
        VStack(spacing: 16) {
            Text("Tracking")
                .font(.title2.bold())
                .padding(.top, 16)

            if trackingViewModel.trackingManager.state.status == .disabled {
                Button {
                    trackingViewModel.enable()
                    showTrackingSheet = false
                } label: {
                    Label("Enable Tracking", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if trackingViewModel.trackingManager.state.isPaused {
                Button {
                    trackingViewModel.resume()
                    showTrackingSheet = false
                } label: {
                    Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                VStack(spacing: 8) {
                    Text("Pause for…").font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(PauseDuration.allCases, id: \.self) { duration in
                            Button(duration.label) {
                                trackingViewModel.pause(for: duration)
                                showTrackingSheet = false
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                Button(role: .destructive) {
                    trackingViewModel.disable()
                    showTrackingSheet = false
                } label: {
                    Label("Disable Tracking", systemImage: "location.slash.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding()
        .presentationDetents([.height(260)])
    }

    // MARK: - Chip styling

    private var chipIcon: String {
        switch trackingViewModel.trackingManager.state.status {
        case .active: return "location.fill"
        case .paused: return "pause.circle.fill"
        case .disabled: return "location.slash"
        }
    }

    private var chipColor: Color {
        switch trackingViewModel.trackingManager.state.status {
        case .active: return .green
        case .paused: return .orange
        case .disabled: return .secondary
        }
    }
}
