import SwiftUI
import SwiftData
import CoreLocation

struct LogbookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var places: [Place]
    @EnvironmentObject var settings: AppSettings
    @State private var visitForAlternatives: Visit?
    @State private var visitToDelete: Visit?
    @State private var showDeleteConfirmation = false
    @State private var refreshID = UUID()
    @State private var trajectoryDay: Date?
    @State private var tripHomeCentroid: TripDetector.HomeCentroid?

    private var logbookVisits: [Visit] {
        let minStay = settings.minStayMinutes
        return places
            .flatMap { $0.visits }
            .filter { $0.isQuickCapture || !$0.journalEntries.isEmpty || $0.durationMinutes >= minStay }
            .sorted { $0.arrivalDate > $1.arrivalDate }
    }

    private var timelineSections: [LogbookTimelineSection] {
        let visits = logbookVisits
        guard !visits.isEmpty else { return [] }

        let home = tripHomeCentroid ?? settings.cachedTripHomeCentroid
        let trips = home.map {
            TripDetector.detectTrips(
                from: visits,
                homeCentroid: $0,
                minDays: settings.tripMinDays,
                minDistanceKm: settings.tripMinDistanceKm
            )
        } ?? []
        let tripVisitIDs = Set(trips.flatMap { $0.visits.map(\.id) })
        let localVisits = visits.filter { !tripVisitIDs.contains($0.id) }

        var sections = trips.map { trip in
            LogbookTimelineSection(
                id: "trip-\(trip.id)",
                title: "Trip · \(Self.tripDateRange(for: trip))",
                icon: "airplane",
                latestDate: trip.endDate,
                kind: .trip(trip)
            )
        }

        let thisWeekInterval = Calendar.current.dateInterval(of: .weekOfYear, for: Date())
        let thisWeek = localVisits.filter { visit in
            thisWeekInterval?.contains(visit.arrivalDate) == true
        }
        let earlier = localVisits.filter { visit in
            thisWeekInterval?.contains(visit.arrivalDate) != true
        }

        if !thisWeek.isEmpty {
            sections.append(LogbookTimelineSection(
                id: "local-this-week",
                title: "This week",
                icon: "calendar",
                latestDate: thisWeek.first?.arrivalDate ?? .distantPast,
                kind: .local(visits: thisWeek)
            ))
        }

        if !earlier.isEmpty {
            sections.append(LogbookTimelineSection(
                id: "local-earlier",
                title: "Earlier",
                icon: "calendar",
                latestDate: earlier.first?.arrivalDate ?? .distantPast,
                kind: .local(visits: earlier)
            ))
        }

        return sections.sorted { $0.latestDate > $1.latestDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if logbookVisits.isEmpty {
                    ContentUnavailableView(
                        "No Visits Yet",
                        systemImage: "book.closed",
                        description: Text("Your logbook will fill up as you visit places with tracking enabled.")
                    )
                } else {
                    List {
                        ForEach(timelineSections) { section in
                            Section {
                                switch section.kind {
                                case .trip(let trip):
                                    TripHeroCard(trip: trip)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                                case .local(let visits):
                                    ForEach(Array(visits.enumerated()), id: \.element.id) { index, visit in
                                        if let place = visit.place {
                                            NavigationLink {
                                                PlaceDetailView(place: place)
                                            } label: {
                                                LocalVisitCompactRow(
                                                    visit: visit,
                                                    place: place,
                                                    nextSameDayArrival: nextSameDayArrival(for: index, in: visits)
                                                ) {
                                                    visitForAlternatives = visit
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                                Button {
                                                    trajectoryDay = Calendar.current.startOfDay(for: visit.arrivalDate)
                                                } label: {
                                                    Label("Map", systemImage: "map")
                                                }
                                                .tint(.blue)
                                            }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button {
                                                    visitToDelete = visit
                                                    showDeleteConfirmation = true
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                                .tint(.red)
                                            }
                                        }
                                    }
                                }
                            } header: {
                                LogbookSectionHeader(icon: section.icon, title: section.title)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .id(refreshID)
                    .onAppear(perform: refreshTripHomeCentroid)
                    .refreshable {
                        refreshTripHomeCentroid()
                        refreshID = UUID()
                    }
                }
            }
            .navigationTitle("Logbook")
            .navigationDestination(item: $trajectoryDay) { day in
                DayTrajectoryView(day: day)
            }
            .sheet(item: $visitForAlternatives) { visit in
                AlternativePlacePicker(visit: visit) {
                    refreshID = UUID()
                }
            }
            .alert("Delete Visit?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let visit = visitToDelete {
                        if let place = visit.place,
                           let index = place.visits.firstIndex(where: { $0.id == visit.id }) {
                            place.visits.remove(at: index)
                        }
                        JournalEntryDeletion.cleanupPhotos(for: visit)
                        modelContext.delete(visit)
                        try? modelContext.save()
                        visitToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    visitToDelete = nil
                }
            } message: {
                Text("This visit will be permanently deleted.")
            }
        }
    }

    private func refreshTripHomeCentroid() {
        let allVisits = places.flatMap { $0.visits }
        if let centroid = TripDetector.homeCentroid(from: allVisits) {
            settings.cachedTripHomeCentroid = centroid
            tripHomeCentroid = centroid
        } else {
            tripHomeCentroid = settings.cachedTripHomeCentroid
        }
    }

    private func nextSameDayArrival(for index: Int, in visits: [Visit]) -> Date? {
        guard index > 0 else { return nil }
        let next = visits[index - 1]
        let current = visits[index]
        return Calendar.current.isDate(next.arrivalDate, inSameDayAs: current.arrivalDate) ? next.arrivalDate : nil
    }

    private static func tripDateRange(for trip: Trip) -> String {
        let calendar = Calendar.current
        let start = trip.startDate
        let end = trip.endDate
        let formatter = DateFormatter()

        if calendar.component(.year, from: start) == calendar.component(.year, from: end) {
            formatter.dateFormat = "MMM d"
            let startText = formatter.string(from: start)
            formatter.dateFormat = calendar.component(.month, from: start) == calendar.component(.month, from: end) ? "d" : "MMM d"
            return "\(startText) - \(formatter.string(from: end))"
        }

        formatter.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

private struct LogbookTimelineSection: Identifiable {
    let id: String
    let title: String
    let icon: String
    let latestDate: Date
    let kind: LogbookTimelineSectionKind
}

private enum LogbookTimelineSectionKind {
    case trip(Trip)
    case local(visits: [Visit])
}

private struct LogbookSectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}

private struct TripHeroCard: View {
    let trip: Trip

    private var title: String {
        if let city = trip.uniquePlaces.compactMap(\.city).first {
            return "Trip to \(city)"
        }
        return trip.uniquePlaces.first?.displayName ?? "Trip"
    }

    private var subtitle: String {
        let days = trip.dayCount == 1 ? "1 day" : "\(trip.dayCount) days"
        return "\(days) · \(Int(trip.distanceFromHomeKm.rounded())) km from home"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            PlacePillRow(places: trip.uniquePlaces)

            HStack(spacing: 10) {
                TripStat(value: "\(trip.uniquePlaces.count)", label: "Places", icon: "mappin.and.ellipse")
                TripStat(value: "\(trip.noteCount)", label: "Notes", icon: "note.text")
                TripStat(value: "\(trip.photoCount)", label: "Photos", icon: "camera")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.20), lineWidth: 1)
        )
        .padding(.vertical, 2)
    }
}

private struct PlacePillRow: View {
    let places: [Place]

    var body: some View {
        let visiblePlaces = Array(places.prefix(3))
        HStack(spacing: 8) {
            ForEach(visiblePlaces, id: \.id) { place in
                HStack(spacing: 4) {
                    Text(place.emoji)
                    Text(place.displayName)
                        .lineLimit(1)
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
            }

            if places.count > visiblePlaces.count {
                Text("+\(places.count - visiblePlaces.count) more")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
            }
        }
    }
}

private struct TripStat: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LocalVisitCompactRow: View {
    let visit: Visit
    let place: Place
    let nextSameDayArrival: Date?
    var onPickAlternative: (() -> Void)?

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: visit.arrivalDate, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(place.emoji)
                    .font(.title3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(relativeTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(visit.effectiveDurationString(cappedAt: nextSameDayArrival))
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
            }

            if !visit.alternativePlaces.isEmpty {
                Button {
                    onPickAlternative?()
                } label: {
                    if visit.placeConfirmed {
                        Label("Place confirmed", systemImage: "checkmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Label("Not the right place?", systemImage: "arrow.triangle.swap")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 40)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Alternative Place Picker

private struct AlternativePlacePicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let visit: Visit
    var onPlaceChanged: (() -> Void)?

    @State private var pendingCandidate: PlaceCandidate?
    @State private var showConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                if let place = visit.place {
                    Section("Current") {
                        Button {
                            confirmPlace()
                        } label: {
                            HStack {
                                Image(systemName: PlaceCategorizer.icon(for: place.category))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.displayName)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if let category = place.category {
                                        Text(category)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("Confirm")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }

                if !visit.alternativePlaces.isEmpty {
                    Section("Did you mean?") {
                        ForEach(visit.alternativePlaces) { candidate in
                            Button {
                                pendingCandidate = candidate
                                showConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: PlaceCategorizer.icon(for: candidate.category))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.name)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 6) {
                                            if let category = candidate.category {
                                                Text(category)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text("\(Int(candidate.distanceMeters))m away")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Alternatives",
                        systemImage: "mappin.slash",
                        description: Text("No other nearby places were found when this visit was recorded.")
                    )
                }
            }
            .navigationTitle("Wrong Place?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Change place?", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {
                    pendingCandidate = nil
                }
                Button("Change") {
                    if let candidate = pendingCandidate {
                        reassignVisit(to: candidate)
                    }
                }
            } message: {
                if let candidate = pendingCandidate {
                    Text("Change this visit from \"\(visit.place?.displayName ?? "Unknown")\" to \"\(candidate.name)\"?")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func confirmPlace() {
        visit.placeConfirmed = true
        try? modelContext.save()
        onPlaceChanged?()
        dismiss()
    }

    private func reassignVisit(to candidate: PlaceCandidate) {
        let threshold = 0.0001
        let descriptor = FetchDescriptor<Place>()
        let allPlaces = (try? modelContext.fetch(descriptor)) ?? []

        let previousPlace = visit.place

        if let oldPlace = previousPlace,
           let index = oldPlace.visits.firstIndex(where: { $0.id == visit.id }) {
            oldPlace.visits.remove(at: index)
        }

        let newPlace: Place
        if let existing = allPlaces.first(where: {
            $0.name == candidate.name &&
            abs($0.latitude - candidate.latitude) < threshold &&
            abs($0.longitude - candidate.longitude) < threshold
        }) {
            newPlace = existing
        } else {
            newPlace = Place(
                name: candidate.name,
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                category: candidate.category,
                city: candidate.city,
                state: candidate.state
            )
            modelContext.insert(newPlace)
        }

        visit.place = newPlace
        visit.placeConfirmed = true

        var remaining = visit.alternativePlaces.filter { $0.id != candidate.id }
        if let prev = previousPlace, prev.id != newPlace.id {
            let alreadyListed = remaining.contains { cand in
                cand.name == prev.name &&
                abs(cand.latitude - prev.latitude) < threshold &&
                abs(cand.longitude - prev.longitude) < threshold
            }
            if !alreadyListed {
                let newCenter = CLLocation(latitude: newPlace.latitude, longitude: newPlace.longitude)
                let prevCenter = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
                remaining.append(PlaceCandidate(
                    name: prev.name,
                    latitude: prev.latitude,
                    longitude: prev.longitude,
                    category: prev.category,
                    city: prev.city,
                    state: prev.state,
                    distanceMeters: prevCenter.distance(from: newCenter)
                ))
            }
        }
        visit.alternativePlaces = remaining

        try? modelContext.save()
        onPlaceChanged?()
        dismiss()
    }
}
