import SwiftUI

struct LogbookVisitRow: View {
    let visit: Visit
    let place: Place
    let nextSameDayArrival: Date?
    var onMarkAccurate: (() -> Void)?
    var onOpenFeedback: (() -> Void)?

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: visit.arrivalDate)
    }

    private var hasPhoto: Bool {
        let start = visit.arrivalDate.addingTimeInterval(-5 * 60)
        let end = (visit.departureDate ?? visit.arrivalDate).addingTimeInterval(5 * 60)
        return place.journalEntries.contains { entry in
            !entry.photoAssetIdentifiers.isEmpty &&
            entry.date >= start &&
            entry.date <= end
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if place.customEmoji != nil {
                    Text(place.emoji)
                        .font(.title3)
                        .frame(width: 28)
                } else {
                    Image(systemName: PlaceCategorizer.icon(for: place.category))
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(place.displayName)
                            .font(.body.weight(.medium))
                        if hasPhoto {
                            Image(systemName: "camera.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        if let category = place.category, !category.isEmpty {
                            Text(category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let city = place.city {
                            Text(city)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(dateString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(visit.effectiveDurationString(cappedAt: nextSameDayArrival))
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                    #if DEBUG
                    ConfidenceBadge(confidence: visit.confidence, accuracy: visit.medianAccuracyMeters)
                    #endif
                }
            }

            feedbackBar
                .padding(.leading, 40)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var feedbackBar: some View {
        if onOpenFeedback == nil {
            EmptyView()
        } else if let verdict = visit.feedbackVerdict {
            Button {
                onOpenFeedback?()
            } label: {
                verdictLabel(verdict)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 16) {
                Button {
                    onMarkAccurate?()
                } label: {
                    Label("Correct", systemImage: "hand.thumbsup")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)

                Button {
                    onOpenFeedback?()
                } label: {
                    Label("Wrong", systemImage: "hand.thumbsdown")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func verdictLabel(_ verdict: PredictionVerdict) -> some View {
        switch verdict {
        case .accurate:
            Label("Marked correct", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .corrected:
            Label("Corrected", systemImage: "arrow.triangle.swap")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .wrong:
            Label("Marked wrong", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }
}

#if DEBUG
struct ConfidenceBadge: View {
    let confidence: PlaceConfidence
    let accuracy: Double?

    private var color: Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }

    private var icon: String {
        switch confidence {
        case .high: return "checkmark.seal.fill"
        case .medium: return "questionmark.diamond.fill"
        case .low: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(confidence.rawValue)
            if let acc = accuracy {
                Text("(\(Int(acc))m)")
            }
        }
        .font(.caption2)
        .foregroundStyle(color)
    }
}
#endif
