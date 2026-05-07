import SwiftUI
import SwiftData
import MapKit

struct DayTrajectoryView: View {
    @Environment(\.modelContext) private var modelContext
    let day: Date

    @State private var rawSamples: [RawLocationSample] = []
    @State private var segments: [TrajectorySegment] = []
    @State private var stats: TrajectoryStats?
    @State private var dayPlaces: [Place] = []
    @State private var selectedPlace: Place?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var dayVisits: [Visit] = []
    @State private var selectedVisit: Visit.ID?
    @State private var showAllSamples = false

    private static let navTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var isPathAvailable: Bool { !segments.isEmpty }

    private var dayRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    var body: some View {
        ZStack {
            Map(position: $cameraPosition, selection: $selectedPlace) {
                TrajectoryPolyline(segments: segments, colorMode: .time)

                if showAllSamples {
                    ForEach(rawSamples, id: \.id) { sample in
                        Annotation(
                            "",
                            coordinate: CLLocationCoordinate2D(
                                latitude: sample.latitude,
                                longitude: sample.longitude
                            )
                        ) {
                            Circle()
                                .fill(Color.blue.opacity(0.7))
                                .frame(width: 6, height: 6)
                                .overlay(
                                    Circle().stroke(Color.white, lineWidth: 1)
                                )
                        }
                    }
                }

                ForEach(rankings(), id: \.id) { ranking in
                    Annotation(
                        ranking.place.displayName,
                        coordinate: ranking.place.coordinate
                    ) {
                        PlaceAnnotationView(ranking: ranking)
                    }
                    .tag(ranking.place)
                }
            }
            .mapStyle(.standard(showsTraffic: false))
            .mapControls {
                MapCompass()
                MapScaleView()
            }

            VStack {
                TrajectoryHeaderCard(day: day, stats: stats, isPathAvailable: isPathAvailable)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Button {
                            showAllSamples.toggle()
                        } label: {
                            Image(systemName: showAllSamples ? "circle.grid.3x3.fill" : "circle.grid.3x3")
                                .font(.title3)
                                .foregroundStyle(showAllSamples ? Color.accentColor : Color.primary)
                                .padding(12)
                                .background(.regularMaterial)
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                        Button {
                            selectedVisit = nil
                            withAnimation {
                                cameraPosition = initialCamera(segments: segments, places: dayPlaces)
                            }
                        } label: {
                            Image(systemName: "scope")
                                .font(.title3)
                                .padding(12)
                                .background(.regularMaterial)
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                    }
                    .padding(.trailing, 16)
                    // 112 = 88 (strip height) + 12 (strip bottom padding) + 12 (gap above strip)
                    .padding(.bottom, dayVisits.isEmpty ? 24 : 112)
                }
            }

            if !dayVisits.isEmpty {
                VStack {
                    Spacer()
                    TrajectoryTimelineStrip(
                        visits: dayVisits,
                        selectedVisitID: selectedVisit,
                        onTapVisit: recenterToVisit
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }

            if !isPathAvailable && dayPlaces.isEmpty {
                emptyOverlay
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedPlace) { place in
            PlaceDetailSheet(place: place)
                .presentationDetents([.medium])
        }
        .task(id: day) {
            await load()
        }
        .onChange(of: showAllSamples) { _, _ in
            rebuildTrajectory()
        }
    }

    private var navTitle: String {
        Self.navTitleFormatter.string(from: day)
    }

    private var emptyOverlay: some View {
        VStack {
            Spacer()
            Text("No location data recorded for this day")
                .font(.callout)
                .padding(12)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 32)
        }
    }

    /// Build a synthetic ranking-per-place so we can reuse PlaceAnnotationView.
    /// `qualifiedStays` and `totalMinutes` here are scoped to this day only.
    private func rankings() -> [PlaceRanking] {
        let range = dayRange
        return dayPlaces.map { place in
            let visitsToday = place.visits.filter {
                $0.arrivalDate >= range.start && $0.arrivalDate < range.end
            }
            let minutesToday = visitsToday.reduce(0) { $0 + $1.durationMinutes }
            return PlaceRanking(
                place: place,
                qualifiedStays: visitsToday.count,
                totalMinutes: minutesToday
            )
        }
    }

    private func load() async {
        let range = dayRange
        let dayStart = range.start
        let dayEnd = range.end

        let sampleDescriptor = FetchDescriptor<RawLocationSample>(
            predicate: #Predicate {
                $0.timestamp >= dayStart
                && $0.timestamp < dayEnd
                && $0.filterStatus != "rejected-accuracy"
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let samples = (try? modelContext.fetch(sampleDescriptor)) ?? []

        let placeDescriptor = FetchDescriptor<Place>()
        let allPlaces = (try? modelContext.fetch(placeDescriptor)) ?? []
        let placesToday = allPlaces.filter { place in
            place.visits.contains { $0.arrivalDate >= dayStart && $0.arrivalDate < dayEnd }
        }

        let visitDescriptor = FetchDescriptor<Visit>(
            predicate: #Predicate {
                $0.arrivalDate >= dayStart && $0.arrivalDate < dayEnd
            },
            sortBy: [SortDescriptor(\.arrivalDate)]
        )
        let visitsToday = (try? modelContext.fetch(visitDescriptor)) ?? []

        self.rawSamples = samples
        self.dayPlaces = placesToday
        self.dayVisits = visitsToday
        self.selectedVisit = nil
        rebuildTrajectory()
        self.cameraPosition = initialCamera(segments: segments, places: placesToday)
    }

    private func rebuildTrajectory() {
        let epsilon: Double = showAllSamples ? 0 : 5
        let builtSegments = TrajectoryBuilder.build(
            samples: rawSamples,
            day: day,
            epsilonMeters: epsilon
        )
        self.segments = builtSegments
        self.stats = TrajectoryBuilder.computeStats(
            segments: builtSegments,
            rawSampleCount: rawSamples.count,
            placeCount: dayPlaces.count
        )
    }

    private func recenterToVisit(_ visit: Visit) {
        guard let place = visit.place else { return }
        selectedVisit = visit.id
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: place.coordinate,
                latitudinalMeters: 200,
                longitudinalMeters: 200
            ))
        }
    }

    private func initialCamera(
        segments: [TrajectorySegment],
        places: [Place]
    ) -> MapCameraPosition {
        var coords: [CLLocationCoordinate2D] = []
        coords.append(contentsOf: segments.flatMap { $0.points.map(\.coordinate) })
        coords.append(contentsOf: places.map(\.coordinate))

        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLon = lons.min(),
              let maxLon = lons.max() else {
            return .automatic
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.005, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.005, (maxLon - minLon) * 1.4)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }
}
