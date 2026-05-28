import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @EnvironmentObject var trackingViewModel: TrackingViewModel
    @EnvironmentObject var quickCapture: QuickCaptureViewModel
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<JournalEntry> { !$0.photoAssetIdentifiers.isEmpty },
        sort: \JournalEntry.date,
        order: .reverse
    )
    private var photoEntries: [JournalEntry]

    @State private var pullOffset: CGFloat = 0
    @State private var isCommitting = false
    @State private var hapticArmed = true

    @State private var selectedPhotoItem: HomePhotoItem?
    @State private var pendingPlaceID: PersistentIdentifier?

    @State private var showTrackingSheet = false
    @State private var showCameraPermissionAlert = false
    @State private var showTrackingOffAlert = false

    private static let pullThreshold: CGFloat = 120
    private static let scrollSpaceName = "home-scroll"

    private var items: [HomePhotoItem] { HomePhotoFeed.flatten(photoEntries) }
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
        .onAppear {
            _ = showTrackingSheet
            _ = showCameraPermissionAlert
            _ = showTrackingOffAlert
            _ = isCommitting
            _ = hapticArmed
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
}

private struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
