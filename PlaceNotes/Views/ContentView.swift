import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var trackingViewModel: TrackingViewModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var quickCapture: QuickCaptureViewModel

    @State private var showCameraPermissionAlert = false

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "photo.on.rectangle")
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
        .fullScreenCover(isPresented: $quickCapture.showCamera) {
            CameraPickerView(
                onCaptured: { image, exif in
                    quickCapture.showCamera = false
                    quickCapture.photoCaptured(image: image, exifLocation: exif)
                },
                onCancelled: {
                    quickCapture.showCamera = false
                    quickCapture.cancelCapture()
                }
            )
            .ignoresSafeArea()
        }
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
        .animation(.easeInOut(duration: 0.2), value: quickCapture.isWorkingInBackground)
        .animation(.easeInOut(duration: 0.2), value: quickCapture.state)
        .onOpenURL { url in handleDeepLink(url) }
        .alert("Camera access needed", isPresented: $showCameraPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable Camera access in Settings → Placelore to capture photos.")
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "placelore", url.host == "capture" else { return }
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
