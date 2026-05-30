import SwiftUI
import SwiftData
import CoreLocation

struct ManualPlacePickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Place.name) private var allPlaces: [Place]

    /// When present, the picker ranks places by distance to this coordinate and offers
    /// to save the photo here directly. Nil when no location is available at all.
    let nearCoordinate: CLLocationCoordinate2D?
    let onPicked: (Place) -> Void
    let onUseCurrentLocation: () -> Void
    let onCancelled: () -> Void

    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty, nearCoordinate != nil {
                    Section {
                        Button {
                            onUseCurrentLocation()
                            dismiss()
                        } label: {
                            Label("Save at my current location", systemImage: "location.fill")
                        }
                    }
                }
                Section(sectionTitle) {
                    if filteredPlaces.isEmpty {
                        Text("No matching places")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredPlaces) { place in
                            Button {
                                onPicked(place)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(place.displayName)
                                    if let city = place.city {
                                        Text(city).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Pick a place")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancelled()
                        dismiss()
                    }
                }
            }
        }
    }

    private var sectionTitle: LocalizedStringKey {
        nearCoordinate == nil ? "Recent places" : "Nearby places"
    }

    private var filteredPlaces: [Place] {
        ManualPlacePickerRanking.rank(allPlaces, near: nearCoordinate, search: search)
    }
}

/// Pure ranking/filtering logic for the manual place picker, extracted for unit testing.
enum ManualPlacePickerRanking {
    static let unsearchedLimit = 20

    static func rank(
        _ places: [Place],
        near coordinate: CLLocationCoordinate2D?,
        search: String,
        limit: Int = unsearchedLimit
    ) -> [Place] {
        let ordered: [Place]
        if let coordinate {
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            ordered = places.sorted {
                origin.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                    < origin.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
            }
        } else {
            ordered = places
        }

        let trimmed = search.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(ordered.prefix(limit)) }
        let needle = trimmed.lowercased()
        return ordered.filter { $0.displayName.lowercased().contains(needle) }
    }
}
