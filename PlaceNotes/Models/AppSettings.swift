import CoreLocation
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

    @Published var trackingState: TrackingState {
        didSet {
            if let data = try? JSONEncoder().encode(trackingState) {
                UserDefaults.standard.set(data, forKey: "trackingState")
            }
        }
    }

    @Published var homeLatitude: Double? {
        didSet {
            if let homeLatitude {
                UserDefaults.standard.set(homeLatitude, forKey: "homeLatitude")
            } else {
                UserDefaults.standard.removeObject(forKey: "homeLatitude")
            }
        }
    }

    @Published var homeLongitude: Double? {
        didSet {
            if let homeLongitude {
                UserDefaults.standard.set(homeLongitude, forKey: "homeLongitude")
            } else {
                UserDefaults.standard.removeObject(forKey: "homeLongitude")
            }
        }
    }

    @Published var homeCentroidComputedAt: Date? {
        didSet {
            if let homeCentroidComputedAt {
                UserDefaults.standard.set(homeCentroidComputedAt, forKey: "homeCentroidComputedAt")
            } else {
                UserDefaults.standard.removeObject(forKey: "homeCentroidComputedAt")
            }
        }
    }

    @Published var tripMinDays: Int {
        didSet { UserDefaults.standard.set(tripMinDays, forKey: "tripMinDays") }
    }

    @Published var tripMinDistanceKm: Double {
        didSet { UserDefaults.standard.set(tripMinDistanceKm, forKey: "tripMinDistanceKm") }
    }

    var homeCoordinate: CLLocationCoordinate2D? {
        guard let homeLatitude, let homeLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: homeLatitude, longitude: homeLongitude)
    }

    private init() {
        let savedMin = UserDefaults.standard.integer(forKey: "minStayMinutes")
        self.minStayMinutes = savedMin > 0 ? savedMin : 30

        let savedMilestones = UserDefaults.standard.array(forKey: "milestoneVisitCounts") as? [Int]
        self.milestoneVisitCounts = savedMilestones ?? [5, 10, 25, 50, 100]

        let savedRetention = UserDefaults.standard.integer(forKey: "rawLocationRetentionDays")
        self.rawLocationRetentionDays = savedRetention > 0 ? savedRetention : 30

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

        if UserDefaults.standard.object(forKey: "homeLatitude") != nil {
            self.homeLatitude = UserDefaults.standard.double(forKey: "homeLatitude")
        } else {
            self.homeLatitude = nil
        }

        if UserDefaults.standard.object(forKey: "homeLongitude") != nil {
            self.homeLongitude = UserDefaults.standard.double(forKey: "homeLongitude")
        } else {
            self.homeLongitude = nil
        }

        self.homeCentroidComputedAt = UserDefaults.standard.object(forKey: "homeCentroidComputedAt") as? Date

        let savedMinDays = UserDefaults.standard.integer(forKey: "tripMinDays")
        self.tripMinDays = savedMinDays > 0 ? savedMinDays : 2

        let savedMinKm = UserDefaults.standard.double(forKey: "tripMinDistanceKm")
        self.tripMinDistanceKm = savedMinKm > 0 ? savedMinKm : 50
    }
}
