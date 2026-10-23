import SwiftUI

/// Overlay button for the full-screen photo viewers that copies the photo
/// into the system Photos library.
struct SaveToPhotosButton: View {
    let item: PhotoLibraryExporter.Item
    @StateObject private var viewModel = PhotoLibrarySaveViewModel()

    var body: some View {
        Button {
            viewModel.save([item], announcesSuccess: false)
        } label: {
            icon
                .font(.title)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(viewModel.status != .idle)
        .accessibilityLabel(viewModel.status == .saved ? Text("Saved to Photos") : Text("Save to Photos"))
        .onChange(of: viewModel.status) { _, status in
            if status == .saved {
                AccessibilityNotification.Announcement(String(localized: "Saved to Photos")).post()
            }
        }
        .saveToPhotosAlert(viewModel)
    }

    @ViewBuilder
    private var icon: some View {
        switch viewModel.status {
        case .idle:
            Image(systemName: "arrow.down.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.5))
        case .saving:
            ProgressView().tint(.white)
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
        }
    }
}

extension View {
    func saveToPhotosAlert(_ viewModel: PhotoLibrarySaveViewModel) -> some View {
        modifier(SaveToPhotosAlertModifier(viewModel: viewModel))
    }
}

private struct SaveToPhotosAlertModifier: ViewModifier {
    @ObservedObject var viewModel: PhotoLibrarySaveViewModel

    func body(content: Content) -> some View {
        content.alert(
            viewModel.outcome?.title ?? "",
            isPresented: Binding(
                get: { viewModel.outcome != nil },
                set: { if !$0 { viewModel.outcome = nil } }
            ),
            presenting: viewModel.outcome
        ) { outcome in
            if outcome.offersSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { outcome in
            Text(outcome.message)
        }
    }
}
