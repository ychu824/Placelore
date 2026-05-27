import AVFoundation
import SwiftUI
import UIKit
import os

private let logger = Logger(subsystem: "dev.placelore.app", category: "CameraSession")

/// Owns the live `AVCaptureSession` behind the Dynamic Island camera screen.
/// Configuration and start/stop run on a private serial queue; published
/// state is mutated on the main actor for SwiftUI binding.
@MainActor
final class CameraSession: ObservableObject {

    enum Flash: CaseIterable {
        case off, on, auto

        var avMode: AVCaptureDevice.FlashMode {
            switch self {
            case .off: return .off
            case .on: return .on
            case .auto: return .auto
            }
        }

        var symbol: String {
            switch self {
            case .off: return "bolt.slash.fill"
            case .on: return "bolt.fill"
            case .auto: return "bolt.badge.a.fill"
            }
        }

        var next: Flash {
            switch self {
            case .off: return .on
            case .on: return .auto
            case .auto: return .off
            }
        }
    }

    let session = AVCaptureSession()

    @Published private(set) var isRunning = false
    @Published var flash: Flash = .off
    @Published private(set) var position: AVCaptureDevice.Position = .back

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "dev.placelore.camera-session")
    private var currentInput: AVCaptureDeviceInput?
    private var isConfigured = false

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded()
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let running = self.session.isRunning
            Task { @MainActor in self.isRunning = running }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor in self.isRunning = false }
        }
    }

    func flip() {
        let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back
        position = newPosition
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.addVideoInput(position: newPosition)
            self.session.commitConfiguration()
        }
    }

    func cycleFlash() {
        flash = flash.next
    }

    /// Captures a single still. Returns nil if no camera is available
    /// (e.g. Simulator) or the capture fails.
    func capturePhoto() async -> UIImage? {
        guard isRunning else { return nil }
        let flashMode = flash.avMode
        let isFront = position == .front
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let delegate = PhotoCaptureDelegate { image in
                continuation.resume(returning: image)
            }
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                if let connection = self.photoOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = isFront
                    }
                }
                let settings = AVCapturePhotoSettings()
                if self.photoOutput.supportedFlashModes.contains(flashMode) {
                    settings.flashMode = flashMode
                }
                self.photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    // MARK: - Configuration (sessionQueue only)

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        addVideoInput(position: .back)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        session.commitConfiguration()
        isConfigured = true
    }

    private func addVideoInput(position: AVCaptureDevice.Position) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else {
            logger.error("No camera input for position \(position.rawValue, privacy: .public)")
            return
        }
        if let currentInput {
            session.removeInput(currentInput)
        }
        if session.canAddInput(input) {
            session.addInput(input)
            currentInput = input
        }
    }
}

/// One-shot delegate that retains itself until the capture completes — AVFoundation
/// holds its delegate weakly, so this keeps the callback alive without shared state
/// on `CameraSession`.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void
    private var retain: PhotoCaptureDelegate?

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
        super.init()
        retain = self
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { retain = nil }
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        completion(image)
    }
}

/// Hosts an `AVCaptureVideoPreviewLayer` as the view's backing layer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection,
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}
