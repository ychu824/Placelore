import SwiftUI

struct PullToCapturePill: View {
    let progress: Double          // 0...1
    let isCommitting: Bool        // true while morphing to fullscreen

    private var restWidth: CGFloat { 132 }
    private var restHeight: CGFloat { 32 }
    private var maxDragWidth: CGFloat { 212 }
    private var maxDragHeight: CGFloat { 60 }
    private var viewfinderWidth: CGFloat { 220 }
    private var viewfinderHeight: CGFloat { 160 }

    private var crossedThreshold: Bool { progress >= 1.0 }

    private var width: CGFloat {
        if isCommitting {
            return UIScreen.main.bounds.width
        }
        if crossedThreshold {
            return viewfinderWidth
        }
        return restWidth + (maxDragWidth - restWidth) * progress
    }

    private var height: CGFloat {
        if isCommitting {
            return UIScreen.main.bounds.height
        }
        if crossedThreshold {
            return viewfinderHeight
        }
        return restHeight + (maxDragHeight - restHeight) * progress
    }

    private var cornerRadius: CGFloat {
        if isCommitting { return 0 }
        return crossedThreshold ? 24 : height / 2
    }

    private var labelText: String {
        if crossedThreshold { return "Release to capture" }
        if progress > 0.5 { return "↓ Keep pulling" }
        return "📸 Pull to capture"
    }

    private var labelOpacity: Double {
        if crossedThreshold { return 1 }
        return max(0, 1 - progress * 1.8)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillStyle)
            if crossedThreshold && !isCommitting {
                Image(systemName: "camera.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }
            Text(labelText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .opacity(labelOpacity)
        }
        .frame(width: width, height: height)
    }

    private var fillStyle: AnyShapeStyle {
        if crossedThreshold || isCommitting {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.23, blue: 0.29),
                    Color(red: 0.05, green: 0.09, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        } else {
            return AnyShapeStyle(Color.black)
        }
    }
}

#Preview("Rest") { PullToCapturePill(progress: 0, isCommitting: false) }
#Preview("Half") { PullToCapturePill(progress: 0.5, isCommitting: false) }
#Preview("Threshold") { PullToCapturePill(progress: 1.0, isCommitting: false) }
#Preview("Committing") { PullToCapturePill(progress: 1.0, isCommitting: true) }
