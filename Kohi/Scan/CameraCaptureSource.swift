@preconcurrency import AVFoundation
import CoreMedia
import Observation
import SwiftUI

/// Owns the capture session. Lives off the main actor because everything
/// AVFoundation does here either blocks or arrives on its own queue.
nonisolated final class CameraSession: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "studio.jbk.Kohi.camera")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let tracker = DocumentTracker()

    private let stateLock = NSLock()
    private var isAnalyzing = false
    private var photoContinuation: CheckedContinuation<CGImage?, Never>?

    /// Called from the capture queue for every analysed frame.
    var onDetection: (@Sendable (DocumentTracker.Detection?) -> Void)?

    func configure() {
        session.beginConfiguration()
        // A 4:3 preset keeps the video frames and the still the same shape, so a
        // quad measured on the preview scales straight onto the photo.
        session.sessionPreset = .photo

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            configureFocus(on: device)
        }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        session.commitConfiguration()

        // Portrait only, so the rotation is a constant rather than a coordinator.
        for connection in [videoOutput.connection(with: .video), photoOutput.connection(with: .video)] {
            guard let connection, connection.isVideoRotationAngleSupported(90) else { continue }
            connection.videoRotationAngle = 90
        }
    }

    private func configureFocus(on device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.unlockForConfiguration()
    }

    func start() {
        queue.async { [self] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
        tracker.reset()
    }

    /// The unsmoothed quad from the most recent frame, which is what a capture
    /// should be corrected against.
    var currentQuad: Quad? { tracker.latestRawQuad }

    func capturePhoto() async -> CGImage? {
        await withCheckedContinuation { continuation in
            stateLock.lock()
            guard photoContinuation == nil else {
                stateLock.unlock()
                continuation.resume(returning: nil)
                return
            }
            photoContinuation = continuation
            stateLock.unlock()

            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Claims the analysis slot, or reports that a frame is already in flight.
    private func beginAnalysis() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isAnalyzing else { return false }
        isAnalyzing = true
        return true
    }

    private func endAnalysis() {
        stateLock.lock()
        isAnalyzing = false
        stateLock.unlock()
    }

    private func finishPhoto(with image: CGImage?) {
        stateLock.lock()
        let continuation = photoContinuation
        photoContinuation = nil
        stateLock.unlock()
        continuation?.resume(returning: image)
    }
}

nonisolated extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Detection is slower than the frame rate, so frames are dropped rather
        // than queued. Falling behind the camera would make the overlay lag.
        guard beginAnalysis() else { return }

        let frame = VideoFrame(sampleBuffer: sampleBuffer)
        Task { [tracker, onDetection] in
            let detection = await tracker.analyze(frame)
            onDetection?(detection)
            self.endAnalysis()
        }
    }
}

nonisolated extension CameraSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            finishPhoto(with: nil)
            return
        }
        finishPhoto(with: ImageCodec.decodeOriented(data))
    }
}

/// The scan flow's state, as the views see it.
@Observable
final class ScanEngine {
    private(set) var detection: DocumentTracker.Detection?
    private(set) var isCapturing = false
    private(set) var isDenied = false
    /// Bumped whenever the tracker locks, to drive the haptic.
    private(set) var lockCount = 0
    /// Bumped when the shutter fires.
    private(set) var captureCount = 0

    var onCapture: ((CapturedCard) -> Void)?

    @ObservationIgnored private let camera = CameraSession()
    @ObservationIgnored private var wasLocking = false

    var session: AVCaptureSession { camera.session }

    func start() async {
        guard await requestAccess() else {
            isDenied = true
            return
        }
        camera.onDetection = { [weak self] detection in
            Task { @MainActor in self?.apply(detection) }
        }
        camera.configure()
        camera.start()
    }

    func stop() {
        camera.stop()
    }

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    private func apply(_ detection: DocumentTracker.Detection?) {
        withAnimation(Motion.tracking) {
            self.detection = detection
        }

        let isLocking = detection?.coaching.progress ?? 0 > 0
        if isLocking, !wasLocking {
            lockCount += 1
        }
        wasLocking = isLocking

        if detection?.shouldCapture == true {
            Task { await capture() }
        }
    }

    /// Fires the shutter. Used by auto-capture and by the manual button.
    func capture() async {
        guard !isCapturing else { return }
        isCapturing = true
        captureCount += 1

        let frameSize = detection?.frameSize
        let quad = camera.currentQuad
        let image = await camera.capturePhoto()
        isCapturing = false

        guard let image else { return }

        // The quad was measured on a preview frame; scale it onto the still.
        let scaled: Quad? = {
            guard let quad, let frameSize, frameSize.width > 0 else { return nil }
            return quad.scaled(by: CGFloat(image.width) / frameSize.width)
        }()

        onCapture?(CapturedCard(image: image, quad: scaled))
    }
}

/// Hosts the preview layer. The layer is the view's backing layer so it resizes
/// without any manual frame bookkeeping.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// The custom scan flow: live preview, an outline that follows the card, one
/// line of coaching, and a shutter that usually fires itself.
struct CameraCaptureView: View {
    let onCapture: (CapturedCard) -> Void
    let onCancel: () -> Void

    @State private var engine = ScanEngine()

    var body: some View {
        ZStack {
            if engine.isDenied {
                deniedState
            } else {
                CameraPreview(session: engine.session)
                    .ignoresSafeArea()
                ScanOverlay(detection: engine.detection)
            }

            controls
        }
        .background(Palette.scanBackdrop)
        .task {
            engine.onCapture = onCapture
            await engine.start()
        }
        .onDisappear { engine.stop() }
        .haptic(.detectionLock, trigger: engine.lockCount)
        .haptic(.capture, trigger: engine.captureCount)
    }

    private var controls: some View {
        VStack {
            HStack {
                Button("Cancel", action: onCancel)
                    .font(Typography.subtitle)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            Button {
                Task { await engine.capture() }
            } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 68, height: 68)
                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 2).padding(-6))
            }
            .buttonStyle(.plain)
            .opacity(engine.isDenied ? 0 : 1)
            .scaleEffect(engine.isCapturing ? Motion.Chrome.shutterPressScale : 1)
            .animation(Motion.quick, value: engine.isCapturing)
            .padding(.bottom, 40)
        }
    }

    private var deniedState: some View {
        VStack(spacing: 12) {
            Text("Camera access is off")
                .font(Typography.coaching)
            Text("Turn it on in Settings to scan cards")
                .font(Typography.subtitle)
                .foregroundStyle(.white.opacity(0.55))
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}
