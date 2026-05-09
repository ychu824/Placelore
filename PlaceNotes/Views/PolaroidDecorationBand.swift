import SwiftUI

/// Renders 0–2 polaroid thumbnails fanned behind the Tracking page shutter.
/// Each polaroid is wrapped in a NavigationLink to the corresponding
/// PlaceDetailView. When `entries` is empty the view renders nothing,
/// preserving a clean shutter-only layout for first-launch users.
struct PolaroidDecorationBand: View {
    let entries: [JournalEntry]

    var body: some View {
        let polaroids = PolaroidSelection.selectFor(entries: entries)
        ZStack {
            ForEach(Array(polaroids.enumerated()), id: \.element.id) { index, entry in
                polaroidLink(for: entry, index: index, total: polaroids.count)
            }
        }
        .frame(height: polaroids.isEmpty ? 0 : 140)
        .allowsHitTesting(!polaroids.isEmpty)
    }

    @ViewBuilder
    private func polaroidLink(for entry: JournalEntry, index: Int, total: Int) -> some View {
        let thumbnail = PolaroidThumbnailView(entry: entry)
            .rotationEffect(rotation(index: index, total: total))
            .offset(offset(index: index, total: total))
            .accessibilityLabel(accessibilityLabel(for: entry))
            .accessibilityHint("Tap to view place")

        if let place = entry.place {
            NavigationLink {
                PlaceDetailView(place: place)
            } label: {
                thumbnail
            }
            .buttonStyle(.plain)
        } else {
            thumbnail
        }
    }

    private func rotation(index: Int, total: Int) -> Angle {
        if total <= 1 { return .degrees(-6) }
        return index == 0 ? .degrees(-10) : .degrees(8)
    }

    private func offset(index: Int, total: Int) -> CGSize {
        if total <= 1 { return CGSize(width: -50, height: 0) }
        return index == 0 ? CGSize(width: -55, height: 0) : CGSize(width: 55, height: 0)
    }

    private func accessibilityLabel(for entry: JournalEntry) -> String {
        let name = entry.place?.displayName ?? "Place"
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let date = formatter.localizedString(for: entry.date, relativeTo: Date())
        return "Photo from \(name), \(date)"
    }
}
