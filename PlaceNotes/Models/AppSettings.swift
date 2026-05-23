import Foundation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var minStayMinutes: Int {
        didSet { UserDefaults.standard.set(minStayMinutes, forKey: "minStayMinutes") }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode") }
    }

    @Published var milestoneVisitCounts: [Int] {
        didSet { UserDefaults.standard.set(milestoneVisitCounts, forKey: "milestoneVisitCounts") }
    }

    @Published var rawLocationRetentionDays: Int {
        didSet { UserDefaults.standard.set(rawLocationRetentionDays, forKey: "rawLocationRetentionDays") }
    }

    @Published var tripMinDays: Int {
        didSet { UserDefaults.standard.set(tripMinDays, forKey: "tripMinDays") }
    }

    @Published var tripMinDistanceKm: Double {
        didSet { UserDefaults.standard.set(tripMinDistanceKm, forKey: "tripMinDistanceKm") }
    }

    @Published var cachedTripHomeLatitude: Double? {
        didSet { Self.setOptional(cachedTripHomeLatitude, forKey: "cachedTripHomeLatitude") }
    }

    @Published var cachedTripHomeLongitude: Double? {
        didSet { Self.setOptional(cachedTripHomeLongitude, forKey: "cachedTripHomeLongitude") }
    }

    var cachedTripHomeCentroid: TripDetector.HomeCentroid? {
        get {
            guard let latitude = cachedTripHomeLatitude,
                  let longitude = cachedTripHomeLongitude else {
                return nil
            }
            return TripDetector.HomeCentroid(latitude: latitude, longitude: longitude)
        }
        set {
            cachedTripHomeLatitude = newValue?.latitude
            cachedTripHomeLongitude = newValue?.longitude
        }
    }

    @Published var trackingState: TrackingState {
        didSet {
            if let data = try? JSONEncoder().encode(trackingState) {
                UserDefaults.standard.set(data, forKey: "trackingState")
            }
        }
    }

    private init() {
        let savedMin = UserDefaults.standard.integer(forKey: "minStayMinutes")
        self.minStayMinutes = savedMin > 0 ? savedMin : 30

        let savedMilestones = UserDefaults.standard.array(forKey: "milestoneVisitCounts") as? [Int]
        self.milestoneVisitCounts = savedMilestones ?? [5, 10, 25, 50, 100]

        let savedRetention = UserDefaults.standard.integer(forKey: "rawLocationRetentionDays")
        self.rawLocationRetentionDays = savedRetention > 0 ? savedRetention : 30

        let savedTripMinDays = UserDefaults.standard.integer(forKey: "tripMinDays")
        self.tripMinDays = savedTripMinDays > 0 ? savedTripMinDays : 2

        let savedTripMinDistance = UserDefaults.standard.double(forKey: "tripMinDistanceKm")
        self.tripMinDistanceKm = savedTripMinDistance > 0 ? savedTripMinDistance : 50

        self.cachedTripHomeLatitude = Self.optionalDouble(forKey: "cachedTripHomeLatitude")
        self.cachedTripHomeLongitude = Self.optionalDouble(forKey: "cachedTripHomeLongitude")

        if let raw = UserDefaults.standard.string(forKey: "appearanceMode"),
           let mode = AppearanceMode(rawValue: raw) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }

        if let data = UserDefaults.standard.data(forKey: "trackingState"),
           let state = try? JSONDecoder().decode(TrackingState.self, from: data) {
            self.trackingState = state
        } else {
            self.trackingState = .default
        }
    }

    private static func optionalDouble(forKey key: String) -> Double? {
        UserDefaults.standard.object(forKey: key) as? Double
    }

    private static func setOptional(_ value: Double?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
