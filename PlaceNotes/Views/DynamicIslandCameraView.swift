import SwiftUI
import UIKit

/// Full-screen capture experience that frames the hardware Dynamic Island as
/// the camera's lens. A live viewfinder sits directly beneath the island; on
/// shutter, the captured photo "prints" downward out of the island slot before
/// being handed back to the QuickCapture pipeline.
///
/// Note: Apple exposes no public API to render a live camera feed inside the
/// real Dynamic Island. This is a screen-aligned illusion — the on-screen UI is
/// positioned around the physical island cutout so the pill reads as the lens.
struct DynamicIslandCameraView: View {
    let onCaptured: (UIImage) -> Void
    let onClose: () -> Void

    @StateObject private var camera = CameraSession()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isCapturing = false
    @State private var shutterFlash = false
    @State private var printing: PrintingPhoto?
    @State private var printProgress: CGFloat = 0

    private struct PrintingPhoto: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    // Slate palette aligned with PhotographicShutterButton.
    private static let bodyTop = Color(red: 0.165, green: 0.227, blue: 0.290)
    private static let bodyBottom = Color(red: 0.078, green: 0.110, blue: 0.149)
    private static let housingFill = Color(red: 0.122, green: 0.169, blue: 0.224)

    var body: some View {
        GeometryReader { proxy in
            // Read insets from the proxy (which respects the safe area) so the
            // island position is known, then ignore the safe area on the ZStack
            // itself so its coordinate origin is the physical screen top.
            let metrics = IslandMetrics(safeTop: proxy.safeAreaInsets.top, width: proxy.size.width)
            let safeBottom = proxy.safeAreaInsets.bottom
            ZStack {
                LinearGradient(
                    colors: [Self.bodyTop, Self.bodyBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )

                mainColumn(metrics: metrics, safeBottom: safeBottom)

                if let printing {
                    printingPolaroid(printing, metrics: metrics, width: proxy.size.width)
                }

                // Occludes the polaroid above the island slot so it reads as
                // emerging from underneath the housing.
                Self.bodyTop
                    .frame(height: metrics.housingBottomY)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                housing(metrics: metrics, width: proxy.size.width)

                topBar(metrics: metrics)

                if shutterFlash {
                    Color.white.transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
        .statusBarHidden(true)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    // MARK: - Layout

    @ViewBuilder
    private func mainColumn(metrics: IslandMetrics, safeBottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.housingBottomY + 24)

            viewfinder
                .padding(.horizontal, 20)

            Spacer(minLength: 24)

            controls
                .padding(.bottom, max(safeBottom, 16) + 24)
        }
    }

    private var viewfinder: some View {
        ZStack {
            if camera.isRunning {
                CameraPreview(session: camera.session)
            } else {
                Color.black
                    .overlay {
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Starting camera…")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.black.opacity(0.35), lineWidth: 6)
                .blur(radius: 3)
                .padding(-4)
        )
        .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
    }

    private var controls: some View {
        HStack {
            Button {
                camera.cycleFlash()
            } label: {
                controlIcon(systemName: camera.flash.symbol)
            }
            .accessibilityLabel("Flash")

            Spacer()

            PhotographicShutterButton(isBusy: isCapturing) {
                capture()
            }

            Spacer()

            Button {
                camera.flip()
            } label: {
                controlIcon(systemName: "arrow.triangle.2.circlepath.camera.fill")
            }
            .accessibilityLabel("Flip camera")
        }
        .padding(.horizontal, 44)
    }

    private func controlIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
            .background(Color.white.opacity(0.12), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
    }

    // MARK: - Island housing & top bar

    @ViewBuilder
    private func housing(metrics: IslandMetrics, width: CGFloat) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Self.housingFill)
                .frame(width: metrics.housingWidth, height: metrics.housingHeight)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .position(x: width / 2, y: metrics.islandCenterY)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func topBar(metrics: IslandMetrics) -> some View {
        VStack {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.14), in: Circle())
                }
                .accessibilityLabel("Close camera")

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, metrics.safeTop + 4)

            Spacer()
        }
    }

    // MARK: - Print animation

    @ViewBuilder
    private func printingPolaroid(_ photo: PrintingPhoto, metrics: IslandMetrics, width: CGFloat) -> some View {
        let polaroidWidth = width * 0.46
        let photoSide = polaroidWidth - 16
        let polaroidHeight = photoSide + 40
        let startY = metrics.islandCenterY
        let endY = metrics.housingBottomY + polaroidHeight / 2 + 36
        let centerY = startY + (endY - startY) * printProgress

        VStack(spacing: 0) {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: photoSide, height: photoSide)
                .clipped()
                .padding(.top, 8)
                .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .frame(width: polaroidWidth, height: polaroidHeight)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
        .rotationEffect(.degrees(-2 * Double(printProgress)))
        .position(x: width / 2, y: centerY)
        .allowsHitTesting(false)
    }

    // MARK: - Actions

    private func capture() {
        guard !isCapturing, printing == nil else { return }
        isCapturing = true

        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.1)) { shutterFlash = true }
        }

        Task { @MainActor in
            let image = await camera.capturePhoto()

            if !reduceMotion {
                withAnimation(.easeIn(duration: 0.2)) { shutterFlash = false }
            } else {
                shutterFlash = false
            }

            guard let image else {
                isCapturing = false
                return
            }

            await runPrintAnimation(image)
            onCaptured(image)
        }
    }

    @MainActor
    private func runPrintAnimation(_ image: UIImage) async {
        printing = PrintingPhoto(image: image)
        printProgress = 0

        if reduceMotion {
            printProgress = 1
            try? await Task.sleep(for: .milliseconds(300))
        } else {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                printProgress = 1
            }
            try? await Task.sleep(for: .milliseconds(850))
        }
    }
}

/// Approximate geometry of the Dynamic Island region. Devices with the island
/// report a top safe-area inset of ~59pt; notch/older devices report less, in
/// which case the housing renders as a decorative lens at the top center.
private struct IslandMetrics {
    let safeTop: CGFloat
    let islandCenterY: CGFloat
    let housingWidth: CGFloat
    let housingHeight: CGFloat
    let housingBottomY: CGFloat

    init(safeTop: CGFloat, width: CGFloat) {
        self.safeTop = safeTop
        let hasIsland = safeTop >= 51

        let islandTop: CGFloat = hasIsland ? 11 : 8
        let islandHeight: CGFloat = hasIsland ? 37.33 : 28
        self.islandCenterY = islandTop + islandHeight / 2

        let extraWidth: CGFloat = 36
        let pillWidth: CGFloat = hasIsland ? 126 : 100
        self.housingWidth = min(pillWidth + extraWidth, width - 80)
        self.housingHeight = islandHeight + 22
        self.housingBottomY = islandCenterY + housingHeight / 2
    }
}
