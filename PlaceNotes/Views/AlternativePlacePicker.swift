import SwiftUI
import SwiftData
import CoreLocation

struct AlternativePlacePicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    let visit: Visit
    var onPlaceChanged: (() -> Void)?

    @State private var pendingCandidate: PlaceCandidate?
    @State private var showConfirmation = false

    var body: some View {
        // Decoded once per render — `visit.alternativePlaces` JSON-decodes on
        // every access.
        let alternatives = visit.alternativePlaces
        NavigationStack {
            List {
                if let place = visit.place {
                    Section("We recorded") {
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
                        }

                        if settings.predictionFeedbackEnabled {
                            Button {
                                markAccurate()
                            } label: {
                                Label("This is correct", systemImage: "hand.thumbsup")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                if !alternatives.isEmpty {
                    Section("Did you mean?") {
                        ForEach(alternatives) { candidate in
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
                }

                if settings.predictionFeedbackEnabled {
                    Section {
                        Button(role: .destructive) {
                            markWrong()
                        } label: {
                            Label(
                                alternatives.isEmpty ? "This is wrong" : "None of these — still wrong",
                                systemImage: "hand.thumbsdown"
                            )
                        }
                    } footer: {
                        Text("Your feedback is logged to measure how well place prediction is working.")
                    }
                }
            }
            .navigationTitle(settings.predictionFeedbackEnabled ? "How did we do?" : "Change Place")
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
        .presentationDetents([.medium, .large])
    }

    private func markAccurate() {
        PredictionFeedbackRecorder.record(.accurate, for: visit, in: modelContext)
        onPlaceChanged?()
        dismiss()
    }

    private func markWrong() {
        PredictionFeedbackRecorder.record(.wrong, for: visit, in: modelContext)
        onPlaceChanged?()
        dismiss()
    }

    private func reassignVisit(to candidate: PlaceCandidate) {
        // Record the corrected feedback while `visit.place` still holds the
        // original prediction, so the snapshot captures what failed.
        PredictionFeedbackRecorder.record(
            .corrected,
            for: visit,
            correctedName: candidate.name,
            correctedCategory: candidate.category,
            correctionSource: "alternative",
            in: modelContext
        )

        let threshold = 0.0001
        let candidateName = candidate.name
        let minLat = candidate.latitude - threshold
        let maxLat = candidate.latitude + threshold
        let minLon = candidate.longitude - threshold
        let maxLon = candidate.longitude + threshold
        let descriptor = FetchDescriptor<Place>(
            predicate: #Predicate<Place> {
                $0.name == candidateName &&
                $0.latitude >= minLat && $0.latitude <= maxLat &&
                $0.longitude >= minLon && $0.longitude <= maxLon
            }
        )

        let previousPlace = visit.place

        if let oldPlace = previousPlace,
           let index = oldPlace.visits.firstIndex(where: { $0.id == visit.id }) {
            oldPlace.visits.remove(at: index)
        }

        let newPlace: Place
        if let existing = (try? modelContext.fetch(descriptor))?.first {
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
