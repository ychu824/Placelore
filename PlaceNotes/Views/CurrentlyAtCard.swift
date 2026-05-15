import SwiftUI
import SwiftData

struct CurrentlyAtCard: View {
    var body: some View {
        EmptyView()
    }
}

enum CurrentlyAtFormatter {
    static func elapsed(arrivalDate: Date, now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(arrivalDate)))
        if total < 60 {
            return String(localized: "Just arrived")
        }
        let totalMinutes = total / 60
        if totalMinutes < 60 {
            return String(format: String(localized: "Arrived %lldm ago"), totalMinutes)
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: String(localized: "Arrived %lldh %lldm ago"), hours, minutes)
    }

    static func priorVisits(_ count: Int) -> String {
        return ""
    }
}
