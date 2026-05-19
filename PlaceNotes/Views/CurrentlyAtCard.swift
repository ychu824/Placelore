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

            actionRow(visit: visit, place: place)
                .disabled(quickCapture.isWorkingInBackground)
        }
        .padding(18)
        .modifier(CardSurface())
        .padding(.horizontal)
        .sheet(isPresented: $showNoteEditor) {
            JournalEntryEditorView(place: place, visit: visit)
        }
    }

    @ViewBuilder
    private func actionRow(visit: Visit, place: Place) -> some View {
        HStack(spacing: 8) {
            actionButton(title: "+ Note", accessibilityLabel: "Add note") {
                showNoteEditor = true
            }
            actionButton(title: "+ Photo", accessibilityLabel: "Add photo") {
                quickCapture.beginCaptureForKnownPlace(place, visit: visit)
            }
            NavigationLink {
                PlaceDetailView(place: place)
            } label: {
                actionLabelText("View place")
                    .background(Color.primary.opacity(0.08), in: Capsule())
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func actionButton(title: LocalizedStringKey, accessibilityLabel: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabelText(title)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .overlay(
                    Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    @ViewBuilder
    private func actionLabelText(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 10)
            .foregroundStyle(Color.accentColor)
    }

    private func metaLine(visit: Visit, place: Place, now: Date) -> String {
        let elapsed = CurrentlyAtFormatter.elapsed(arrivalDate: visit.arrivalDate, now: now)
        let prior = CurrentlyAtFormatter.priorVisits(place.priorVisitCount)
        return "\(elapsed) · \(prior)"
    }
}

private struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 6)
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
