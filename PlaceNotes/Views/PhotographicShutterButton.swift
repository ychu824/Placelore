import SwiftUI

/// The central shutter control on the Tracking page. Pure presentation —
/// state and side-effects are owned by the caller via `isBusy` and `action`.
/// Renders a slate-blue body with a recessed lens, white bezel ring, and a
/// soft drop shadow. Shows a ProgressView while `isBusy` is true.
struct PhotographicShutterButton: View {

    let isBusy: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    private static let bodyTop = Color(red: 0.353, green: 0.478, blue: 0.576)   // #5A7A93
    private static let bodyMid = Color(red: 0.259, green: 0.365, blue: 0.459)   // #425D75
    private static let bodyBottom = Color(red: 0.192, green: 0.278, blue: 0.341) // #314757
    private static let lensTop = Color(red: 0.180, green: 0.263, blue: 0.349)    // #2E4359
    private static let lensBottom = Color(red: 0.114, green: 0.176, blue: 0.239) // #1D2D3D

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Self.bodyTop, Self.bodyMid, Self.bodyBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(LinearGradient(
                        colors: [Self.lensTop, Self.lensBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.45), lineWidth: 1)
                            .blur(radius: 0.8)
                            .offset(y: 1)
                            .mask(Circle().frame(width: 56, height: 56))
                    )

                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 112, height: 112)
            )
            .shadow(color: Self.bodyMid.opacity(0.45), radius: 12, x: 0, y: 6)
            .saturation(isBusy ? 0.7 : 1.0)
            .scaleEffect(isPressed && !reduceMotion ? 0.94 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
            .frame(width: 112, height: 112)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Log this place")
        .accessibilityHint("Captures a photo and records your visit")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isBusy { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
    }
}
