import Foundation
import os

private let logger = Logger(subsystem: "dev.placelore.app", category: "PhotoLibrarySaveViewModel")

@MainActor
final class PhotoLibrarySaveViewModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case saving
        case saved
    }

    struct Outcome: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let offersSettings: Bool
    }

    @Published private(set) var status: Status = .idle
    @Published var outcome: Outcome?

    var isSaving: Bool { status == .saving }

    /// Pass `announcesSuccess: false` when the control itself shows success
    /// (e.g. a checkmark) and an alert would be redundant. Partial failures
    /// and errors are always announced.
    func save(_ items: [PhotoLibraryExporter.Item], announcesSuccess: Bool = true) {
        guard status != .saving else { return }
        status = .saving
        outcome = nil
        Task {
            do {
                let summary = try await PhotoLibraryExporter.save(items)
                status = .saved
                if summary.failed > 0 {
                    let total = summary.saved + summary.failed
                    outcome = Outcome(
                        title: String(localized: "Some Photos Weren't Saved"),
                        message: String(localized: "\(summary.saved) of \(total) photos were added to your Photos library."),
                        offersSettings: false
                    )
                } else if announcesSuccess {
                    outcome = Outcome(
                        title: String(localized: "Saved to Photos"),
                        message: String(localized: "\(summary.saved) photos were added to your Photos library."),
                        offersSettings: false
                    )
                }
            } catch {
                logger.error("Save to Photos failed: \(error.localizedDescription, privacy: .public)")
                status = .idle
                let exportError = error as? PhotoLibraryExporter.ExportError ?? .saveFailed
                outcome = Outcome(
                    title: String(localized: "Couldn't Save to Photos"),
                    message: exportError.localizedDescription,
                    offersSettings: exportError == .accessDenied
                )
            }
        }
    }
}
