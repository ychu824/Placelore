import SwiftUI
import UIKit

struct HeatmapLegendView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var palette: HeatmapPalette {
        colorScheme == .dark ? .dark : .light
    }

    var body: some View {
        HStack(spacing: 12) {
            item("Low",  color: palette.swiftUILow)
            item("Med",  color: palette.swiftUIMid)
            item("High", color: palette.swiftUIHigh)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func item(_ label: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
        }
    }
}
