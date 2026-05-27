import SwiftUI

struct TripHeroCard: View {
    let trip: Trip

    private static let dateRangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var dateRangeString: String {
        let start = Self.dateRangeFormatter.string(from: trip.startDate)
        let end = Self.dateRangeFormatter.string(from: trip.endDate)
        return "\(start) – \(end)"
    }

    private var distanceString: String {
        let km = trip.meanDistanceFromHomeMeters / 1000
        if km >= 100 {
            return String(format: "~%.0f km from home", km)
        }
        return String(format: "~%.1f km from home", km)
    }

    private var placePills: [String] {
        var seen = Set<UUID>()
        var pills: [String] = []
        for v in trip.visits {
            guard let p = v.place, !seen.contains(p.id) else { continue }
            seen.insert(p.id)
            pills.append("\(p.emoji) \(p.displayName)")
            if pills.count >= 3 { break }
        }
        let extras = trip.uniquePlaceCount - pills.count
        if extras > 0 {
            pills.append("+\(extras) more")
        }
        return pills
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("✈️")
                Text(trip.title)
                    .font(.title3.bold())
                Spacer()
                Text(dateRangeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label("\(trip.dayCount) days", systemImage: "calendar")
                    .font(.caption)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(distanceString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 6) {
                ForEach(placePills, id: \.self) { pill in
                    Text(pill)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(.primary)
                }
            }

            HStack(spacing: 16) {
                Label("\(trip.uniquePlaceCount) places", systemImage: "mappin")
                Label("\(trip.journalEntryCount) notes", systemImage: "note.text")
                Label("\(trip.photoCount) photos", systemImage: "photo")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
