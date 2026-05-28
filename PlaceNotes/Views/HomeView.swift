import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @EnvironmentObject var trackingViewModel: TrackingViewModel
    @EnvironmentObject var quickCapture: QuickCaptureViewModel
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \JournalEntry.date, order: .reverse)
    private var allEntries: [JournalEntry]

    @State private var pullOffset: CGFloat = 0
    @State private var isCommitting = false
    @State private var hapticArmed = true
    @State private var peakProgress: Double = 0

    @State private var selectedPhotoItem: HomePhotoItem?
    @State private var pendingPlaceID: PersistentIdentifier?

    @State private var showTrackingSheet = false
    @State private var showCameraPermissionAlert = false
    @State private var showTrackingOffAlert = false

    private static let pullThreshold: CGFloat = 120
    private static let scrollSpaceName = "home-scroll"

    private var items: [HomePhotoItem] { HomePhotoFeed.flatten(allEntries) }
    private var progress: Double {
        PullProgress.progress(distance: pullOffset, threshold: Self.pullThreshold)
    }
    private var isTrackingActive: Bool {
        trackingViewModel.trackingManager.state.status == .active
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                content
                if progress > 0 {
                    Color.black.opacity(0.3 * progress)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                PullToCapturePill(progress: progress, isCommitting: isCommitting)
                    .padding(.top, 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isCommitting)
                    .animation(.easeOut(duration: 0.1), value: progress)
            }
            .navigationBarHidden(true)
            .onChange(of: progress) { oldValue, newValue in
                handleProgressChange(old: oldValue, new: newValue)
            }
            .sheet(isPresented: $showTrackingSheet) { trackingSheet }
            .alert("Camera access needed", isPresented: $showCameraPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enable Camera access in Settings → Placelore to capture photos.")
            }
            .alert("Location access needed", isPresented: Binding(
                get: { trackingViewModel.trackingManager.isPermissionDenied },
                set: { newValue in
                    if !newValue { trackingViewModel.trackingManager.isPermissionDenied = false }
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
            .fullScreenCover(item: $selectedPhotoItem) { item in
                HomePhotoViewer(item: item, pendingPlaceID: $pendingPlaceID)
            }
            .navigationDestination(item: $pendingPlaceID) { placeID in
                if let place = modelContext.model(for: placeID) as? Place {
                    PlaceDetailView(place: place)
                } else {
                    Text("Place unavailable")
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 36)
            trackingChip
            CurrentlyAtCard()
            ScrollView {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: HomeScrollOffsetKey.self,
                        value: proxy.frame(in: .named(Self.scrollSpaceName)).minY
                    )
                }
                .frame(height: 0)

                if items.isEmpty {
                    HomeEmptyState().frame(minHeight: 360)
                } else {
                    HomePhotoGrid(items: items, now: Date()) { item in
                        selectedPhotoItem = item
                    }
                    .padding(.horizontal, 4)
                }
            }
            .coordinateSpace(name: Self.scrollSpaceName)
            .onPreferenceChange(HomeScrollOffsetKey.self) { newOffset in
                pullOffset = max(0, newOffset)
            }
        }
    }

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
            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

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

    private func handleProgressChange(old: Double, new: Double) {
        if PullProgress.didCrossThreshold(old: old, new: new), hapticArmed {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            hapticArmed = false
        } else if new < 1.0 {
            hapticArmed = true
        }

        peakProgress = max(peakProgress, new)

        if !isCommitting,
           peakProgress >= 1.0,
           new < old,
           new < 1.0 {
            let peakAtRelease = peakProgress
            peakProgress = 0
            if peakAtRelease >= 1.0 {
                commit()
            }
        }

        if new == 0 {
            peakProgress = 0
        }
    }

    private func commit() {
        guard !isCommitting else { return }
        isCommitting = true
        if isTrackingActive {
            Task {
                let granted = await CameraPickerView.requestCameraPermission()
                await MainActor.run {
                    if granted {
                        quickCapture.beginCapture()
                    } else {
                        showCameraPermissionAlert = true
                    }
                    isCommitting = false
                }
            }
        } else {
            isCommitting = false
            showTrackingOffAlert = true
        }
    }

    private func attemptCapture() {
        Task {
            let granted = await CameraPickerView.requestCameraPermission()
            await MainActor.run {
                if granted {
                    quickCapture.beginCapture()
                } else {
                    showCameraPermissionAlert = true
                }
            }
        }
    }

    @ViewBuilder
    private var trackingSheet: some View {
        VStack(spacing: 16) {
            Text("Tracking").font(.title2.bold()).padding(.top, 16)
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
                    Label("Disable Tracking", systemImage: "location.slash.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding()
        .presentationDetents([.height(260)])
    }
}

private struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
