import SwiftUI

/// Presents whichever capture source is in use, then the review step, and hands
/// the confirmed scan back. Swapping the whole capture experience is a one line
/// change in `ScanSource`.
struct ScanScreen: View {
    let onScan: (ScanResult) -> Void
    let onCancel: () -> Void

    /// A still waiting to be approved. Its presence is what shows the review.
    @State private var pending: CapturedCard?

    var body: some View {
        Group {
            if let pending {
                ScanReviewScreen(
                    capture: pending,
                    onUse: onScan,
                    // Dropping the still unmounts the review and brings the
                    // camera back, which also restarts the session rather than
                    // leaving it running behind a screen you are reading.
                    onRetake: { self.pending = nil }
                )
                .transition(.opacity)
            } else {
                // No `ignoresSafeArea` here. Each source extends its own preview
                // under the status bar; its buttons must not go with it, or
                // Cancel ends up sitting under the clock where it cannot be hit.
                camera
            }
        }
        .animation(Motion.snappy, value: pending == nil)
        .background(Palette.scanBackdrop.ignoresSafeArea())
    }

    @ViewBuilder
    private var camera: some View {
        #if targetEnvironment(simulator)
        SimulatedCaptureView(onCapture: { pending = $0 }, onCancel: onCancel)
        #else
        switch ScanSource.preferred {
        case .visionKit:
            VisionKitCaptureView(onCapture: { pending = $0 }, onCancel: onCancel)
        case .camera:
            CameraCaptureView(onCapture: { pending = $0 }, onCancel: onCancel)
        }
        #endif
    }
}

#if targetEnvironment(simulator)
/// There is no camera in the simulator, so this stands in for one: it returns a
/// bundled sample as though it had just been scanned. It exists purely so the
/// ingest, persistence and landing animation can be exercised without a device.
struct SimulatedCaptureView: View {
    let onCapture: (CapturedCard) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Palette.scanBackdrop.ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "camera.metering.unknown")
                    .font(.system(size: 34, weight: .light))
                Text("No camera in the simulator")
                    .font(Typography.coaching)
                Text("Capture returns a sample card on a surface")
                    .font(Typography.subtitle)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(.white.opacity(0.8))

            VStack {
                HStack {
                    Button("Cancel", action: onCancel)
                        .font(Typography.subtitle)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                Button(action: shoot) {
                    Circle()
                        .fill(.white)
                        .frame(width: 68, height: 68)
                        .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 2).padding(-6))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 54)
            }
        }
        .task {
            // Lands straight on the review step, which cannot otherwise be
            // reached without a finger.
            if DebugHooks.opensReview { shoot() }
        }
    }

    private func shoot() {
        guard let captured = DebugHooks.sampleCapture() else {
            onCancel()
            return
        }
        onCapture(captured)
    }
}
#endif
