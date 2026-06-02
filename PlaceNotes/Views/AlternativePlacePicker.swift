import SwiftUI
import SwiftData
import CoreLocation

struct AlternativePlacePicker: View {
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
