import SwiftUI
import SwiftData
import CoreLocation

struct LogbookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var places: [Place]
    @EnvironmentObject var settings: AppSettings

    @StateObject private var viewModel = LogbookViewModel()

    @State private var visitForAlternatives: Visit?
    @State private var visitToDelete: Visit?
    @State private var showDeleteConfirmation = false
    @State private var refreshID = UUID()
    @State private var trajectoryDay: Date?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sections.isEmpty {
                    ContentUnavailableView(
                        "No Visits Yet",
                        systemImage: "book.closed",
                        description: Text("Your logbook will fill up as you visit places with tracking enabled.")
                    )
                } else {
                    List {
                        ForEach(viewModel.sections) { section in
                            sectionView(section)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .id(refreshID)
                    .refreshable {
                        viewModel.refresh(places: places, settings: settings)
                        refreshID = UUID()
                    }
                }
            }
            .navigationTitle("Logbook")
            .task(id: places.count) {
                viewModel.refresh(places: places, settings: settings)
            }
            .onChange(of: settings.tripMinDistanceKm) { _, _ in
                viewModel.refresh(places: places, settings: settings)
            }
            .onChange(of: settings.tripMinDays) { _, _ in
                viewModel.refresh(places: places, settings: settings)
            }
            .onChange(of: settings.minStayMinutes) { _, _ in
                viewModel.refresh(places: places, settings: settings)
            }
            .navigationDestination(item: $trajectoryDay) { day in
                DayTrajectoryView(day: day)
            }
            .sheet(item: $visitForAlternatives) { visit in
                AlternativePlacePicker(visit: visit) {
                    viewModel.refresh(places: places, settings: settings)
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
                        viewModel.refresh(places: places, settings: settings)
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

    @ViewBuilder
    private func sectionView(_ section: LogbookSection) -> some View {
        switch section {
        case .trip(let trip):
            Section {
                NavigationLink {
                    TripDetailView(trip: trip)
                } label: {
                    TripHeroCard(trip: trip)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
        case .thisWeek(let visits):
            Section {
                ForEach(Array(visits.enumerated()), id: \.element.id) { idx, visit in
                    visitRow(visit: visit, all: visits, index: idx)
                }
            } header: {
                Label("This week", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        case .earlier(let year, let month, let visits):
            Section {
                ForEach(Array(visits.enumerated()), id: \.element.id) { idx, visit in
                    visitRow(visit: visit, all: visits, index: idx)
                }
            } header: {
                Text(earlierHeader(year: year, month: month))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private func visitRow(visit: Visit, all: [Visit], index: Int) -> some View {
        if let place = visit.place {
            let nextSameDay: Date? = {
                let nextIdx = index - 1
                guard nextIdx >= 0 else { return nil }
                let next = all[nextIdx]
                return Calendar.current.isDate(next.arrivalDate, inSameDayAs: visit.arrivalDate) ? next.arrivalDate : nil
            }()
            NavigationLink {
                PlaceDetailView(place: place)
            } label: {
                LogbookVisitRow(visit: visit, place: place, nextSameDayArrival: nextSameDay) {
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

    private func earlierHeader(year: Int, month: Int) -> String {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        let date = Calendar.current.date(from: comps) ?? Date()
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
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

