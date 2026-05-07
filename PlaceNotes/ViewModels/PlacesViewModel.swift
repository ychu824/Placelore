import Foundation
import SwiftData

@MainActor
final class PlacesViewModel: ObservableObject {
    @Published var weeklyPlaces: [PlaceRanking] = []
    @Published var monthlyPlaces: [PlaceRanking] = []

    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    func refresh(places: [Place]) {
        let now = Date()
        let calendar = Calendar.current
        guard
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now),
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now)
        else {
            weeklyPlaces = []
            monthlyPlaces = []
            return
        }

        weeklyPlaces = ReportGenerator.frequentPlaces(
            from: places,
            since: sevenDaysAgo,
            minStayMinutes: settings.minStayMinutes
        )

        monthlyPlaces = ReportGenerator.frequentPlaces(
            from: places,
            since: thirtyDaysAgo,
            minStayMinutes: settings.minStayMinutes
        )
    }
}
