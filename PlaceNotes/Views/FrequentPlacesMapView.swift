import SwiftUI
import MapKit
import SwiftData
import UIKit

struct FrequentPlacesMapView: View {
    @Query private var places: [Place]
    @Query(sort: \Visit.arrivalDate) private var visits: [Visit]
    @StateObject private var viewModel = PlacesViewModel()
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var trackingViewModel: TrackingViewModel

    @AppStorage("mapOverlayMode") private var overlayModeRaw: String = OverlayMode.heatmap.rawValue
    @State private var window: TimeWindow = TimeWindow(
        endDate: Date(),
        lengthDays: 15,
        firstVisitDate: nil
    )
    @State private var selectedPlace: Place?
    @State private var showTrackingAlert = false
    @State private var showPathToast = false
    @State private var pathToastShown = false
    @State private var recenterTrigger = 0

    private var overlayMode: OverlayMode {
        OverlayMode(rawValue: overlayModeRaw) ?? .heatmap
    }

    private func setOverlayMode(_ mode: OverlayMode) {
        overlayModeRaw = mode.rawValue
        if mode == .path && window.effectiveLengthDays > 7 && !pathToastShown {
            showPathToast = true
            pathToastShown = true
        }
    }

    private var windowVisits: [Visit] {
        VisitWindowFilter.visits(in: window, from: visits)
    }

    private var weightedPoints: [WeightedPoint] {
        VisitWindowFilter.weighted(windowVisits)
    }

    private var placesInWindow: Set<UUID> {
        Set(windowVisits.compactMap { $0.place?.id })
    }

    private var rankings: [PlaceRanking] {
        var rankings = Array(viewModel.monthlyPlaces.prefix(50))
        let included = Set(rankings.map { $0.place.id })
        let extras = places
            .filter { !$0.journalEntries.isEmpty && !included.contains($0.id) }
            .map { PlaceRanking(place: $0, qualifiedStays: 0, totalMinutes: 0) }
        rankings.append(contentsOf: extras)
        return rankings
    }

    private var chipText: String {
        let n = windowVisits.count
        return String(format: String(localized: "%d visits · %@"), n, window.label)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                modePicker
                ZStack(alignment: .topLeading) {
                    MapPathSamplesProvider(
                        window: window,
                        isPathMode: overlayMode == .path
                    ) { pathSamples in
                        MapContainerView(
                            overlayMode: overlayMode,
                            window: window,
                            weightedPoints: weightedPoints,
                            pathSamples: pathSamples,
                            rankings: rankings,
                            placesInWindow: placesInWindow,
                            userLocation: locationManager.userLocation,
                            onSelectPlace: { selectedPlace = $0 },
                            recenterTrigger: $recenterTrigger
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    floatingChip
                        .padding(12)

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            recenterButton
                                .padding(.trailing, 16)
                                .padding(.bottom, 16)
                        }
                    }
                }

                if overlayMode == .heatmap {
                    HeatmapLegendView()
                }

                TimeWindowScrubber(
                    window: $window,
                    firstVisitDate: visits.first?.arrivalDate
                )
            }
            .padding(.horizontal, 4)
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedPlace) { place in
                PlaceDetailSheet(place: place) {
                    selectedPlace = nil
                    viewModel.refresh(places: places)
                }
                .presentationDetents([.medium])
            }
            .alert("Path shows last 7 days only", isPresented: $showPathToast) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Narrow the time window to 7 days or less to see the full path.")
            }
            .alert("Tracking Disabled", isPresented: $showTrackingAlert) {
                Button("Enable Tracking") { trackingViewModel.enable() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enable tracking to see your current location on the map.")
            }
            .onAppear {
                viewModel.refresh(places: places)
                window.firstVisitDate = visits.first?.arrivalDate
            }
            .onChange(of: visits.first?.arrivalDate) { _, newDate in
                window.firstVisitDate = newDate
            }
        }
    }

    // MARK: - Sub-views

    private var modePicker: some View {
        Picker("Overlay", selection: Binding(
            get: { overlayMode },
            set: { setOverlayMode($0) }
        )) {
            ForEach(OverlayMode.allCases) { mode in
                Label(mode.label, systemImage: mode.sfSymbol).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 4)
    }

    private var floatingChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LinearGradient(
                    colors: [.yellow, .red],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 10, height: 10)
            Text(chipText)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private var recenterButton: some View {
        Button {
            if trackingViewModel.trackingManager.state.status == .disabled {
                showTrackingAlert = true
            } else {
                recenterTrigger &+= 1
            }
        } label: {
            Image(systemName: "location.fill")
                .font(.title3)
                .padding(12)
                .background(.regularMaterial)
                .clipShape(Circle())
                .shadow(radius: 2)
        }
    }
}

private struct MapPathSamplesProvider<Content: View>: View {
    @Query private var samples: [RawLocationSample]
    private let content: ([RawLocationSample]) -> Content

    init(
        window: TimeWindow,
        isPathMode: Bool,
        @ViewBuilder content: @escaping ([RawLocationSample]) -> Content
    ) {
        self.content = content

        let capStart = Calendar.current.date(
            byAdding: .day,
            value: -7,
            to: window.endDate
        ) ?? window.endDate
        let start = isPathMode ? max(window.startDate, capStart) : Date.distantFuture
        let end = isPathMode ? window.endDate : Date.distantPast
        _samples = Query(
            filter: #Predicate<RawLocationSample> {
                $0.timestamp >= start
                && $0.timestamp <= end
                && $0.filterStatus != "rejected-accuracy"
            },
            sort: [SortDescriptor(\.timestamp)]
        )
    }

    var body: some View {
        content(samples)
    }
}

// MARK: - Annotation Data Models

protocol MapAnnotationItem: Identifiable {
    var id: String { get }
    var coordinate: CLLocationCoordinate2D { get }
}

struct SingleItem: MapAnnotationItem {
    let ranking: PlaceRanking

    /// Includes displayName and emoji so a rename or category change forces
    /// SwiftUI to rebuild the Annotation — its label is captured at body time.
    var id: String { "single-\(ranking.place.id)-\(ranking.place.displayName)-\(ranking.place.emoji)" }
    var coordinate: CLLocationCoordinate2D { ranking.place.coordinate }
}

struct ClusterItem: MapAnnotationItem {
    let coordinate: CLLocationCoordinate2D
    let rankings: [PlaceRanking]

    /// Stable ID derived from sorted member place IDs.
    var id: String {
        let memberIDs = rankings.map { $0.place.id.uuidString }.sorted().joined(separator: "+")
        return "cluster-\(memberIDs)"
    }

    var totalVisits: Int {
        rankings.reduce(0) { $0 + $1.qualifiedStays }
    }
}

// MARK: - Annotation Views

struct PlaceAnnotationView: View {
    let ranking: PlaceRanking
    @State private var pulse = false

    private var flameIntensity: FlameIntensity {
        FlameIntensity(visitCount: ranking.qualifiedStays)
    }

    private var borderGradient: LinearGradient {
        let colors: [Color]
        switch flameIntensity {
        case .none:
            colors = [.white.opacity(0.6), .white.opacity(0.6)]
        case .warm:
            colors = [Color(red: 1.0, green: 0.8, blue: 0.4), .orange]
        case .hot:
            colors = [.orange, Color(red: 1.0, green: 0.42, blue: 0)]
        case .blazing:
            colors = [.orange, .red, Color(red: 0.78, green: 0, blue: 0)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var borderWidth: CGFloat {
        flameIntensity == .none ? 1 : 2
    }

    private var fillGradient: LinearGradient {
        let colors: [Color]
        switch flameIntensity {
        case .none:
            colors = [.clear, .clear]
        case .warm:
            colors = [Color.yellow.opacity(0.30), Color.orange.opacity(0.35)]
        case .hot:
            colors = [Color.orange.opacity(0.40), Color(red: 1.0, green: 0.42, blue: 0).opacity(0.45)]
        case .blazing:
            colors = [Color.orange.opacity(0.45), Color.red.opacity(0.55)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var glowColor: Color {
        switch flameIntensity {
        case .none:    return .clear
        case .warm:    return .orange.opacity(0.45)
        case .hot:     return .orange.opacity(0.60)
        case .blazing: return .red.opacity(0.65)
        }
    }

    private var glowRadius: CGFloat {
        switch flameIntensity {
        case .none:    return 0
        case .warm:    return 8
        case .hot:     return 12
        case .blazing: return 18
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(ranking.place.emoji)
                .font(.system(size: 18))

            if ranking.qualifiedStays > 0 {
                Circle()
                    .fill(.black.opacity(0.3))
                    .frame(width: 4, height: 4)

                Text("\(ranking.qualifiedStays)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, 10)
        .padding(.trailing, ranking.qualifiedStays > 0 ? 14 : 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(fillGradient))
        )
        .overlay(Capsule().strokeBorder(borderGradient, lineWidth: borderWidth))
        .shadow(color: glowColor, radius: glowRadius)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .scaleEffect(pulse ? 1.04 : 1.0)
        .onAppear {
            guard flameIntensity == .blazing else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct ClusterAnnotationView: View {
    let cluster: ClusterItem

    private var topEmojis: String {
        cluster.rankings.prefix(2).map { $0.place.emoji }.joined()
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(topEmojis)
                .font(.system(size: 18))
                .tracking(-2)

            Circle()
                .fill(.black.opacity(0.3))
                .frame(width: 4, height: 4)

            Text("\(cluster.rankings.count)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 8)
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

// MARK: - Place Detail Sheet

struct PlaceDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let place: Place
    var onDelete: (() -> Void)?

    @State private var showDeleteConfirmation = false
    @State private var showRenameDialog = false
    @State private var renameText = ""
    @State private var showCategoryPicker = false
    @State private var showPlaceDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(place.emoji)
                    .font(.largeTitle)

                VStack(alignment: .leading, spacing: 4) {
                    Text(place.displayName)
                        .font(.title2.bold())

                    if place.nickname != nil {
                        Text(place.name)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if let category = place.category {
                        Text(category)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            LabeledContent("Total Visits", value: "\(place.visits.count)")
            LabeledContent("Total Time", value: "\(place.totalTrackedMinutes) min")

            if let lastVisit = place.visits.sorted(by: { $0.arrivalDate > $1.arrivalDate }).first {
                LabeledContent("Last Visit", value: lastVisit.arrivalDate.formatted(date: .abbreviated, time: .shortened))
            }

            Spacer()

            Button {
                showPlaceDetail = true
            } label: {
                Label("Journal & Photos", systemImage: "book.pages")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 12) {
                Button {
                    renameText = place.displayName
                    showRenameDialog = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    showCategoryPicker = true
                } label: {
                    Label("Category", systemImage: "tag")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Place", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(place: place)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showPlaceDetail) {
            NavigationStack {
                PlaceDetailView(place: place)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showPlaceDetail = false }
                        }
                    }
            }
        }
        .alert("Rename Place", isPresented: $showRenameDialog) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    place.nickname = trimmed
                    try? modelContext.save()
                }
            }
            Button("Reset to Original", role: .destructive) {
                place.nickname = nil
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Original name: \(place.name)")
        }
        .alert("Delete Place?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                JournalEntryDeletion.cleanupPhotos(for: place)
                for visit in place.visits {
                    modelContext.delete(visit)
                }
                modelContext.delete(place)
                try? modelContext.save()
                onDelete?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \"\(place.displayName)\" and all \(place.visits.count) recorded visits? This cannot be undone.")
        }
    }
}

// MARK: - Category Picker Sheet

struct CategoryPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomCategory.name) private var customCategories: [CustomCategory]
    let place: Place

    @State private var showCustomCategory = false
    @State private var customName = ""
    @State private var customEmoji = ""

    private let columns = [GridItem(.adaptive(minimum: 72))]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Current category
                    HStack(spacing: 8) {
                        Text(place.emoji)
                            .font(.title)
                        Text(place.category ?? "Uncategorized")
                            .font(.headline)
                        Spacer()
                        Text("Current")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Built-in categories
                    Text("Built-in Categories")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(PlaceCategorizer.categoryMap, id: \.label) { entry in
                            let isSelected = place.category == entry.label && place.customEmoji == nil
                            Button {
                                place.category = entry.label
                                place.customEmoji = nil
                                try? modelContext.save()
                                dismiss()
                            } label: {
                                VStack(spacing: 4) {
                                    Text(PlaceCategorizer.emoji(for: entry.label))
                                        .font(.title2)
                                    Text(entry.label)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // User-created categories (if any exist)
                    if !customCategories.isEmpty {
                        Text("Your Categories")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(customCategories) { entry in
                                let isSelected = place.category == entry.name && place.customEmoji == entry.emoji
                                Button {
                                    place.category = entry.name
                                    place.customEmoji = entry.emoji
                                    try? modelContext.save()
                                    dismiss()
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(entry.emoji)
                                            .font(.title2)
                                        Text(entry.name)
                                            .font(.caption2)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Create new custom category
                    Text("New Custom Category")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    if showCustomCategory {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                EmojiTextField(text: $customEmoji, placeholder: "Tap")
                                    .frame(width: 56, height: 44)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                TextField("Category name", text: $customName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button {
                                let trimmedName = customName.trimmingCharacters(in: .whitespaces)
                                let trimmedEmoji = customEmoji.trimmingCharacters(in: .whitespaces)
                                guard !trimmedName.isEmpty, !trimmedEmoji.isEmpty else { return }
                                // Save as a persistent custom category if it doesn't already exist
                                let alreadyExists = customCategories.contains {
                                    $0.name == trimmedName && $0.emoji == trimmedEmoji
                                }
                                if !alreadyExists {
                                    modelContext.insert(CustomCategory(name: trimmedName, emoji: trimmedEmoji))
                                }
                                place.category = trimmedName
                                place.customEmoji = trimmedEmoji
                                try? modelContext.save()
                                dismiss()
                            } label: {
                                Text("Save Custom Category")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                      customEmoji.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button {
                            customName = place.category ?? ""
                            customEmoji = place.customEmoji ?? ""
                            showCustomCategory = true
                        } label: {
                            Label("Create New Category", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("Change Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Emoji Keyboard Text Field

/// A UITextField wrapper that opens the emoji keyboard directly.
struct EmojiTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeUIView(context: Context) -> UIEmojiTextField {
        let field = UIEmojiTextField()
        field.placeholder = placeholder
        field.font = .systemFont(ofSize: 32)
        field.textAlignment = .center
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UIEmojiTextField, context: Context) {
        if uiView.text != text { uiView.text = text }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty { return true }
            return string.allSatisfy { $0.isEmoji }
        }

        @objc func textChanged(_ sender: UITextField) {
            // Keep only the last emoji (handles multi-scalar emoji like flags/families)
            guard let value = sender.text, !value.isEmpty else {
                text = ""
                return
            }
            let lastEmoji = String(value[value.index(before: value.endIndex)...])
            text = lastEmoji
            sender.text = lastEmoji
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            textField.text = text
        }
    }
}

private extension Character {
    var isEmoji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation ||
            (scalar.properties.isEmoji && scalar.value > 0x238C)
        }
    }
}

/// UITextField subclass that forces the emoji keyboard.
class UIEmojiTextField: UITextField {
    override var textInputMode: UITextInputMode? {
        for mode in UITextInputMode.activeInputModes {
            if mode.primaryLanguage == "emoji" {
                return mode
            }
        }
        return super.textInputMode
    }
}
