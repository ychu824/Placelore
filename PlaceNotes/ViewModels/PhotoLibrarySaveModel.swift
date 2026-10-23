import Foundation
import os

private let logger = Logger(subsystem: "dev.placelore.app", category: "PhotoLibrarySaveModel")

/// Drives a "Save to Photos" control: tracks progress and surfaces the
/// outcome as an alert.
@MainActor
final class PhotoLibrarySaveModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case saving
        case saved
    }

    struct Outcome: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let isAccessDenied: Bool
    }

    @Published private(set) var status: Status = .idle
    @Published var outcome: Outcome?

    var isSaving: Bool { status == .saving }

    /// Pass `announcesSuccess: false` when the control itself shows success
    /// (e.g. a checkmark) and an alert would be redundant.
    func save(_ items: [PhotoLibraryExporter.Item], announcesSuccess: Bool = true) {
        guard status != .saving else { return }
        status = .saving
        Task {
            do {
                let count = try await PhotoLibraryExporter.save(items)
                status = .saved
                if announcesSuccess {
                    outcome = Outcome(
                        title: String(localized: "Saved to Photos"),
                        message: count == 1
                            ? String(localized: "1 photo was added to your Photos library.")
                            : String(localized: "\(count) photos were added to your Photos library."),
                        isAccessDenied: false
                    )
                }
            } catch {
                logger.error("Save to Photos failed: \(error.localizedDescription, privacy: .public)")
                status = .idle
                outcome = Outcome(
                    title: String(localized: "Couldn't Save to Photos"),
                    message: error.localizedDescription,
                    isAccessDenied: (error as? PhotoLibraryExporter.ExportError) == .accessDenied
                )
            }
        }
    }
}
