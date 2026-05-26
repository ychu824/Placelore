import SwiftUI
import Charts

struct PlaceStatsCharts: View {
    let place: Place

    private var visits: [Visit] { place.visits }
    private var monthData: [VisitStats.MonthBucket] { VisitStats.monthBuckets(for: visits) }
    private var hourData: [VisitStats.HourBucket] { VisitStats.hourBuckets(for: visits) }
    private var weekdayData: [VisitStats.WeekdayBucket] { VisitStats.weekdayBuckets(for: visits) }
    private var insight: PlaceInsight.Insight? { PlaceInsight.summarize(visits: visits) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            chartCard(title: "Visits per month") { monthChart }
            chartCard(title: "Time of day") { hourChart }
            if let insight {
                insightBanner(insight)
            }
            chartCard(title: "Day of week") { weekdayChart }
        }
    }

    @ViewBuilder
    private func chartCard<Content: View>(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(height: 140)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func insightBanner(_ insight: PlaceInsight.Insight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 3)
            HStack(spacing: 6) {
                Text(insight.emoji)
                Text(insight.text)
                    .font(.footnote)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.trailing, 12)
        .background(Color.yellow.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var monthChart: some View {
        Chart(monthData) { bucket in
            BarMark(
                x: .value("Month", bucket.label),
                y: .value("Visits", bucket.count)
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel()
                AxisTick()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    private var hourChart: some View {
        Chart(hourData) { bucket in
            BarMark(
                x: .value("Hour", bucket.id),
                y: .value("Visits", bucket.count)
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(hourLabel(hour))
                    }
                }
                AxisTick()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    private var weekdayChart: some View {
        Chart(weekdayData) { bucket in
            BarMark(
                x: .value("Day", bucket.label),
                y: .value("Visits", bucket.count)
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0:  return "12a"
        case 6:  return "6a"
        case 12: return "12p"
        case 18: return "6p"
        default: return "\(hour)"
        }
    }
}
