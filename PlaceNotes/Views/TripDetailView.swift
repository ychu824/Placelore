import SwiftUI
import MapKit

struct TripDetailView: View {
    let trip: Trip

    @State private var selectedPlace: Place?
    @State private var visitForAlternatives: Visit?
    @State private var trajectoryDay: Date?
    @State private var refreshID = UUID()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private var uniquePlaces: [Place] {
        var seen = Set<UUID>()
        var places: [Place] = []
        for v in trip.visits {
            if let p = v.place, !seen.contains(p.id) {
                seen.insert(p.id)
                places.append(p)
            }
        }
        return places
    }

    private var visitsByDay: [(date: Date, visits: [Visit])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: trip.visits) { cal.startOfDay(for: $0.arrivalDate) }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (date: $0.key, visits: $0.value.sorted { $0.arrivalDate < $1.arrivalDate }) }
    }

    private var initialCameraPosition: MapCameraPosition {
        let span = MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        return .region(MKCoordinateRegion(center: trip.centroid, span: span))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Map(initialPosition: initialCameraPosition) {
                    ForEach(uniquePlaces) { place in
                        Marker(place.displayName, coordinate: place.coordinate)
                    }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 16) {
                    Label("\(trip.dayCount) days", systemImage: "calendar")
                    Label("\(trip.uniquePlaceCount) places", systemImage: "mappin")
                    Label("\(trip.photoCount) photos", systemImage: "photo")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                ForEach(visitsByDay, id: \.date) { day in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Self.dayFormatter.string(from: day.date))
                                .font(.headline)
                            Spacer()
                            Button {
                                trajectoryDay = day.date
                            } label: {
                                Label("Map", systemImage: "map")
                                    .font(.subheadline)
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                        }
                        .padding(.top, 8)

                        ForEach(Array(day.visits.enumerated()), id: \.element.id) { idx, visit in
                            if let place = visit.place {
                                let nextSameDay: Date? = {
                                    let nextIdx = idx + 1
                                    guard nextIdx < day.visits.count else { return nil }
                                    return day.visits[nextIdx].arrivalDate
                                }()
                                Button {
                                    selectedPlace = place
                                } label: {
                                    LogbookVisitRow(visit: visit, place: place, nextSameDayArrival: nextSameDay) {
                                        visitForAlternatives = visit
                                    }
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .id(refreshID)
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedPlace) { place in
            PlaceDetailView(place: place)
        }
        .navigationDestination(item: $trajectoryDay) { day in
            DayTrajectoryView(day: day)
        }
        .sheet(item: $visitForAlternatives) { visit in
            AlternativePlacePicker(visit: visit) {
                refreshID = UUID()
            }
        }
    }
}
