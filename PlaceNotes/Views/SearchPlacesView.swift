import SwiftUI
import SwiftData

struct SearchPlacesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var places: [Place]
    @EnvironmentObject var settings: AppSettings

    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var selectedCity: String?
    @State private var selectedState: String?
    @State private var showFilters = false

    private var availableCategories: [String] {
        Array(Set(places.compactMap(\.category))).sorted()
    }

    private var availableCities: [String] {
        Array(Set(places.compactMap(\.city))).sorted()
    }

    private var availableStates: [String] {
        Array(Set(places.compactMap(\.state))).sorted()
    }

    private var filteredPlaces: [Place] {
        let minStay = settings.minStayMinutes
        // Qualified stats are computed once per place up front — calling
        // qualifiedStayCount/totalQualifiedMinutes inside the sort comparator
        // re-filters the whole visit array on every comparison.
        return places
            .compactMap { place -> (place: Place, stays: Int, minutes: Int)? in
                let qualified = place.qualifiedStays(minMinutes: minStay)
                guard !qualified.isEmpty else { return nil }
                let minutes = qualified.reduce(0) { $0 + $1.durationMinutes }
                return (place, qualified.count, minutes)
            }
            .filter { entry in
                let place = entry.place
                if searchText.isEmpty { return true }
                let query = searchText.lowercased()
                return place.displayName.lowercased().contains(query)
                    || (place.name.lowercased().contains(query))
                    || (place.nickname?.lowercased().contains(query) ?? false)
                    || (place.category?.lowercased().contains(query) ?? false)
                    || (place.city?.lowercased().contains(query) ?? false)
                    || (place.state?.lowercased().contains(query) ?? false)
            }
            .filter { entry in
                if let cat = selectedCategory { return entry.place.category == cat }
                return true
            }
            .filter { entry in
                if let city = selectedCity { return entry.place.city == city }
                return true
            }
            .filter { entry in
                if let state = selectedState { return entry.place.state == state }
                return true
            }
            .sorted { ($0.stays, $0.minutes) > ($1.stays, $1.minutes) }
            .map(\.place)
    }

    private var hasActiveFilters: Bool {
        selectedCategory != nil || selectedCity != nil || selectedState != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showFilters {
                    filterBar
                }

                if filteredPlaces.isEmpty {
                    Spacer()
                    if searchText.isEmpty && !hasActiveFilters {
                        ContentUnavailableView(
                            "No Places Yet",
                            systemImage: "magnifyingglass",
                            description: Text("Visit places with tracking enabled to search them here.")
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                    Spacer()
                } else {
                    List(filteredPlaces, id: \.id) { place in
                        SearchPlaceRow(place: place, minStayMinutes: settings.minStayMinutes)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Name, category, city, or state")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            showFilters.toggle()
                        }
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "Category",
                    selection: $selectedCategory,
                    options: availableCategories
                )

                FilterChip(
                    title: "City",
                    selection: $selectedCity,
                    options: availableCities
                )

                FilterChip(
                    title: "State",
                    selection: $selectedState,
                    options: availableStates
                )

                if hasActiveFilters {
                    Button("Clear") {
                        selectedCategory = nil
                        selectedCity = nil
                        selectedState = nil
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct FilterChip: View {
    let title: String
    @Binding var selection: String?
    let options: [String]

    var body: some View {
        Menu {
            Button("All") {
                selection = nil
            }
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    HStack {
                        Text(option)
                        if selection == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection ?? title)
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selection != nil ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
            .foregroundStyle(selection != nil ? Color.accentColor : .primary)
            .clipShape(Capsule())
        }
    }
}

private struct SearchPlaceRow: View {
    let place: Place
    let minStayMinutes: Int

    var body: some View {
        HStack(spacing: 12) {
            if place.customEmoji != nil {
                Text(place.emoji)
                    .font(.title3)
                    .frame(width: 28)
            } else {
                Image(systemName: PlaceCategorizer.icon(for: place.category))
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(place.displayName)
                    .font(.body.weight(.medium))

                if place.nickname != nil {
                    Text(place.name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 6) {
                    if let category = place.category, !category.isEmpty {
                        Text(category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let city = place.city, let state = place.state {
                        Text("\(city), \(state)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let city = place.city {
                        Text(city)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let state = place.state {
                        Text(state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(place.qualifiedStayCount(minMinutes: minStayMinutes)) visits")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.accentColor)
                Text("\(place.totalQualifiedMinutes(minMinutes: minStayMinutes)) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
