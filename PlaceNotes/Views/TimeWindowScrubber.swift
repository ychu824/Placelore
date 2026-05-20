import SwiftUI

struct TimeWindowScrubber: View {
    @Binding var window: TimeWindow
    let firstVisitDate: Date?

    private var maxOffsetDays: Double {
        guard let first = firstVisitDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0
        return Double(max(0, days - window.lengthDays))
    }

    private var offsetDays: Binding<Double> {
        Binding(
            get: {
                let d = Calendar.current.dateComponents([.day], from: window.endDate, to: Date()).day ?? 0
                return Double(max(0, d))
            },
            set: { newValue in
                let clamped = max(0, min(newValue, maxOffsetDays))
                if let newEnd = Calendar.current.date(byAdding: .day, value: -Int(clamped), to: Date()) {
                    window.endDate = newEnd
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Time window")
                    .font(.caption2.smallCaps())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(window.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            if maxOffsetDays > 0 {
                Slider(
                    value: offsetDays,
                    in: 0...maxOffsetDays,
                    step: 1
                )
                .tint(.orange)
            } else {
                Slider(value: .constant(0), in: 0...1)
                    .disabled(true)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 4)
    }
}
