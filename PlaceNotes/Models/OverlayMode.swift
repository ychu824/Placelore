import Foundation

enum OverlayMode: String, CaseIterable, Identifiable {
    case heatmap
    case pins
    case path

    var id: String { rawValue }

    var label: String {
        switch self {
        case .heatmap: return String(localized: "Heatmap")
        case .pins:    return String(localized: "Pins")
        case .path:    return String(localized: "Path")
        }
    }

    var sfSymbol: String {
        switch self {
        case .heatmap: return "flame.fill"
        case .pins:    return "mappin"
        case .path:    return "scribble.variable"
        }
    }
}
