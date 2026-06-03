import SwiftUI
import SwiftData

struct LogbookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var places: [Place]
    @EnvironmentObject var settings: AppSettings

    @StateObject private var viewModel = LogbookViewModel()

    @Query private var feedbackRecords: [PredictionFeedback]
    @State private var visitForFeedback: Visit?
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
            .sheet(item: $visitForFeedback) { visit in
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
                LogbookVisitRow(
                    visit: visit,
                    place: place,
                    nextSameDayArrival: nextSameDay,
                    feedbackVerdict: feedbackRecords.first { $0.visitID == visit.id }?.verdict,
                    onMarkAccurate: {
                        PredictionFeedbackRecorder.record(.accurate, for: visit, in: modelContext)
                        viewModel.refresh(places: places, settings: settings)
                        refreshID = UUID()
                    },
                    onOpenFeedback: {
                        visitForFeedback = visit
                    }
                )
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
