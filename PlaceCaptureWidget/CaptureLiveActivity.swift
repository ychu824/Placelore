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
                        Text(context.state.placeName ?? "Placelore")
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
                    Link(destination: CaptureActivityAttributes.captureURL) {
                        Label("Capture a moment", systemImage: "camera.fill")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.15), in: Capsule())
                    }
                }
            } compactLeading: {
                Image(systemName: "camera.fill")
            } compactTrailing: {
                Text("Capture")
                    .font(.caption2.weight(.semibold))
            } minimal: {
                Image(systemName: "camera.fill")
            }
            .widgetURL(CaptureActivityAttributes.captureURL)
            .keylineTint(.green)
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
                Text(state.placeName ?? "Placelore")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("Tap to capture a moment")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }
}
