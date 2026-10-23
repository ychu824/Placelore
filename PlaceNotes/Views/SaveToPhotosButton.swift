import SwiftUI

/// Overlay button for the full-screen photo viewers that copies the photo
/// into the system Photos library.
struct SaveToPhotosButton: View {
    let item: PhotoLibraryExporter.Item
    @StateObject private var model = PhotoLibrarySaveModel()

    var body: some View {
        Button {
            model.save([item], announcesSuccess: false)
        } label: {
            icon
                .font(.title)
                .frame(width: 36, height: 36)
        }
        .disabled(model.status != .idle)
        .accessibilityLabel(model.status == .saved ? Text("Saved to Photos") : Text("Save to Photos"))
        .saveToPhotosAlert(model)
    }

    @ViewBuilder
    private var icon: some View {
        switch model.status {
        case .idle:
            Image(systemName: "square.and.arrow.down.fill")
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
    func saveToPhotosAlert(_ model: PhotoLibrarySaveModel) -> some View {
        modifier(SaveToPhotosAlertModifier(model: model))
    }
}

private struct SaveToPhotosAlertModifier: ViewModifier {
    @ObservedObject var model: PhotoLibrarySaveModel

    func body(content: Content) -> some View {
        content.alert(
            model.outcome?.title ?? "",
            isPresented: Binding(
                get: { model.outcome != nil },
                set: { if !$0 { model.outcome = nil } }
            ),
            presenting: model.outcome
        ) { outcome in
            if outcome.isAccessDenied {
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
