import SwiftUI
import SwiftData

struct CurrentlyAtCard: View {
    var body: some View {
        EmptyView()
    }
}

enum CurrentlyAtFormatter {
    static func elapsed(arrivalDate: Date, now: Date) -> String {
        return ""
    }

    static func priorVisits(_ count: Int) -> String {
        return ""
    }
}
