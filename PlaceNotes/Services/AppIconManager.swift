import UIKit
import os

@MainActor
enum AppIconManager {
    private static let logger = Logger(subsystem: "dev.placelore.app", category: "AppIcon")

    struct Option: Identifiable, Hashable {
        let id: String
        let displayName: String
        let alternateName: String?
        let previewAsset: String
    }

    static let options: [Option] = [
        Option(id: "outdoor", displayName: "Outdoor", alternateName: nil, previewAsset: "AppIconPreview-Outdoor"),
        Option(id: "day", displayName: "Day", alternateName: "AppIcon", previewAsset: "AppIconPreview-Day"),
        Option(id: "night", displayName: "Night", alternateName: "AppIcon-Night", previewAsset: "AppIconPreview-Night")
    ]

    static var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    static var currentOption: Option {
        let name = UIApplication.shared.alternateIconName
        return options.first { $0.alternateName == name } ?? options[0]
    }

    static func setIcon(_ option: Option, completion: ((Error?) -> Void)? = nil) {
        guard UIApplication.shared.supportsAlternateIcons else {
            completion?(nil)
            return
        }
        guard option.alternateName != UIApplication.shared.alternateIconName else {
            completion?(nil)
            return
        }
        UIApplication.shared.setAlternateIconName(option.alternateName) { error in
            if let error {
                logger.error("setAlternateIconName failed: \(error.localizedDescription)")
            }
            completion?(error)
        }
    }
}
