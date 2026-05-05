import SwiftUI

struct TrajectoryTimelineStrip: View {
    let visits: [Visit]
    let selectedVisitID: Visit.ID?
    let onTapVisit: (Visit) -> Void

    fileprivate static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(visits.compactMap(VisitRow.init), id: \.visit.id) { row in
                    TimelineCard(
                        row: row,
                        isSelected: row.visit.id == selectedVisitID
                    ) {
                        onTapVisit(row.visit)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(height: 88)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

private struct VisitRow {
    let visit: Visit
    let place: Place

    init?(visit: Visit) {
        guard let place = visit.place else { return nil }
        self.visit = visit
        self.place = place
    }
}

private struct TimelineCard: View {
    let row: VisitRow
    let isSelected: Bool
    let onTap: () -> Void

    private var arrivalString: String {
        TrajectoryTimelineStrip.timeFormatter.string(from: row.visit.arrivalDate)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(row.place.emoji)
                    .font(.title2)
                Text(arrivalString)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text(row.visit.durationString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 84, height: 76)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
