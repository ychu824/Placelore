import ActivityKit
import SwiftUI
import WidgetKit

struct CaptureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CaptureActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .widgetURL(CaptureActivityAttributes.captureURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.green)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Tracking")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        DwellSubtitle(state: context.state)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Link(destination: CaptureActivityAttributes.captureURL) {
                            Label("Capture a moment", systemImage: "camera.fill")
                                .font(.callout.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(.white.opacity(0.15), in: Capsule())
                        }
                    }
                }
            } compactLeading: {
                Text("📸")
            } compactTrailing: {
                Label("Capture", systemImage: "camera.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.2), in: Capsule())
            } minimal: {
                Text("📸")
            }
            .widgetURL(CaptureActivityAttributes.captureURL)
            .keylineTint(.green)
        }
    }
}

/// Live "time here · prior visits" line that mirrors the home card's meta row.
/// Uses a relative-style date so the elapsed label updates on its own without
/// the app having to push activity updates.
private struct DwellSubtitle: View {
    let state: CaptureActivityAttributes.ContentState

    var body: some View {
        if let arrivalDate = state.arrivalDate {
            Label {
                Text("\(arrivalDate, style: .relative) · \(state.priorVisitsText)")
                    .lineLimit(1)
            } icon: {
                Image(systemName: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct LockScreenView: View {
    let state: CaptureActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.green.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if state.arrivalDate != nil {
                    DwellSubtitle(state: state)
                } else {
                    Text("Tap to capture a moment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
    }
}
