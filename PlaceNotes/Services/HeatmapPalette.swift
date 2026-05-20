import SwiftUI
import UIKit

enum HeatmapPalette {
    case light
    case dark

    static func forStyle(_ style: UIUserInterfaceStyle) -> HeatmapPalette {
        style == .dark ? .dark : .light
    }

    /// 3-stop gradient. Light = yellow → orange → red.
    /// Dark = cyan → magenta → white (legible over dark map tiles).
    var stops: (low: UIColor, mid: UIColor, high: UIColor) {
        switch self {
        case .light:
            return (
                low:  UIColor(red: 1.00, green: 0.80, blue: 0.00, alpha: 1),
                mid:  UIColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 1),
                high: UIColor(red: 0.86, green: 0.16, blue: 0.16, alpha: 1)
            )
        case .dark:
            return (
                low:  UIColor(red: 0.20, green: 0.85, blue: 0.95, alpha: 1),
                mid:  UIColor(red: 0.85, green: 0.20, blue: 0.85, alpha: 1),
                high: UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
            )
        }
    }

    /// Maps an intensity in [0,1] to RGBA, alpha-curved so low values fade out.
    func rgba(for intensity: Double) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let t = max(0, min(1, intensity))
        let alpha = UInt8(min(255, max(0, t * 220)))
        let s = stops
        let from: UIColor
        let to: UIColor
        let local: Double
        if t < 0.5 {
            from = s.low; to = s.mid; local = t / 0.5
        } else {
            from = s.mid; to = s.high; local = (t - 0.5) / 0.5
        }
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let r = r1 + (r2 - r1) * local
        let g = g1 + (g2 - g1) * local
        let b = b1 + (b2 - b1) * local
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255), alpha)
    }

    var swiftUILow: Color  { Color(stops.low) }
    var swiftUIMid: Color  { Color(stops.mid) }
    var swiftUIHigh: Color { Color(stops.high) }
}
