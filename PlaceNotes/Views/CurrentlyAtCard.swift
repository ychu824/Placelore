import SwiftUI
import SwiftData

struct CurrentlyAtCard: View {
    @Query(
        filter: #Predicate<Visit> { $0.departureDate == nil },
        sort: \Visit.arrivalDate,
        order: .reverse
    ) private var openVisits: [Visit]

    @EnvironmentObject private var quickCapture: QuickCaptureViewModel
    @State private var showNoteEditor = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let cutoff = context.date.addingTimeInterval(-48 * 3600)
            if let visit = openVisits.first(where: { $0.arrivalDate > cutoff }),
               let place = visit.place {
                cardBody(visit: visit, place: place, now: context.date)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func cardBody(visit: Visit, place: Place, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("📍 You're at")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(place.displayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(metaLine(visit: visit, place: place, now: now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                actionButton(title: "+ Note") {
                    showNoteEditor = true
                }
                actionButton(title: "+ Photo") {
                    quickCapture.beginCaptureForKnownPlace(place, visit: visit)
                }
                NavigationLink {
                    PlaceDetailView(place: place)
                } label: {
                    actionLabel(title: "View place")
                }
                .buttonStyle(.plain)
            }
            .disabled(quickCapture.isWorkingInBackground)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 4)
        .padding(.horizontal)
        .sheet(isPresented: $showNoteEditor) {
            JournalEntryEditorView(place: place, visit: visit)
        }
    }

    @ViewBuilder
    private func actionButton(title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title: title)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actionLabel(title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 10)
            .background(Color.black.opacity(0.06), in: Capsule())
            .foregroundStyle(.primary)
    }

    private func metaLine(visit: Visit, place: Place, now: Date) -> String {
        let elapsed = CurrentlyAtFormatter.elapsed(arrivalDate: visit.arrivalDate, now: now)
        let prior = CurrentlyAtFormatter.priorVisits(place.priorVisitCount)
        return "\(elapsed) · \(prior)"
    }
}

enum CurrentlyAtFormatter {
    static func elapsed(arrivalDate: Date, now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(arrivalDate)))
        if total < 60 {
            return String(localized: "Just arrived")
        }
        let totalMinutes = total / 60
        if totalMinutes < 60 {
            return String(format: String(localized: "Arrived %lldm ago"), totalMinutes)
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: String(localized: "Arrived %lldh %lldm ago"), hours, minutes)
    }

    static func priorVisits(_ count: Int) -> String {
        let clamped = max(0, count)
        if clamped == 0 {
            return String(localized: "First visit here")
        }
        if clamped == 1 {
            return String(format: String(localized: "%lld prior visit"), 1)
        }
        return String(format: String(localized: "%lld prior visits"), clamped)
    }
}
