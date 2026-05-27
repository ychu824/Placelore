import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var trackingViewModel: TrackingViewModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var quickCapture: QuickCaptureViewModel

    var body: some View {
        TabView {
            TrackingControlView()
                .tabItem {
                    Label("Tracking", systemImage: "location.fill")
                }

            LogbookView()
                .tabItem {
                    Label("Logbook", systemImage: "book.fill")
                }

            FrequentPlacesMapView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }

            SearchPlacesView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(.accentColor)
        .sheet(isPresented: Binding(
            get: { quickCapture.state == .manualPickNeeded },
            set: { newValue in
                if !newValue, quickCapture.state == .manualPickNeeded {
                    quickCapture.cancelCapture()
                }
            }
        )) {
            ManualPlacePickerView(
                onPicked: { place in
                    if let id = quickCapture.pendingPhotoAssetId {
                        quickCapture.manualPlaceSelected(place, photoAssetId: id)
                    }
                },
                onCancelled: { quickCapture.cancelCapture() }
            )
        }
        .alert("Capture failed", isPresented: Binding(
            get: { if case .error = quickCapture.state { return true } else { return false } },
            set: { if !$0 { quickCapture.cancelCapture() } }
        )) {
            Button("OK") { quickCapture.cancelCapture() }
        } message: {
            if case let .error(msg) = quickCapture.state { Text(msg) }
        }
        .overlay(alignment: .top) {
            if quickCapture.isWorkingInBackground {
                BackgroundWorkPill(state: quickCapture.state)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if case let .done(payload) = quickCapture.state {
                QuickCaptureToast(
                    payload: payload,
                    onUndo: { quickCapture.undoNewVisit(payload) },
                    onSplit: { quickCapture.splitFromMerge(payload) },
                    onDismiss: { quickCapture.cancelCapture() }
                )
                .padding(.bottom, 70)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if quickCapture.showCamera {
                DynamicIslandCameraView(
                    onCaptured: { image in
                        quickCapture.photoCaptured(image: image, exifLocation: nil)
                        quickCapture.showCamera = false
                    },
                    onClose: { quickCapture.cancelCapture() }
                )
                .transition(.dynamicIslandExpand)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: quickCapture.isWorkingInBackground)
        .animation(.easeInOut(duration: 0.2), value: quickCapture.state)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: quickCapture.showCamera)
    }
}

extension AnyTransition {
    /// Grows the camera page out of the Dynamic Island pill at top-center,
    /// so opening the camera reads as the island expanding.
    static var dynamicIslandExpand: AnyTransition {
        .scale(scale: 0.06, anchor: UnitPoint(x: 0.5, y: 0.04))
            .combined(with: .opacity)
    }
}

private struct BackgroundWorkPill: View {
    let state: QuickCaptureViewModel.State

    private var label: String {
        switch state {
        case .savingPhoto: return "Saving photo…"
        case .resolvingPlace: return "Resolving place…"
        default: return ""
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 3, y: 1)
    }
}
