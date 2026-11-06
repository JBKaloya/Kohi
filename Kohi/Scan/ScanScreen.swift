import SwiftUI

/// Presents whichever capture source is in use, then the review step, and hands
/// the confirmed scan back. The camera stays mounted behind the review so the
/// session is not destroyed and rebuilt on retake.
struct ScanScreen: View {
    let onScan: (ScanResult) -> Void
    let onCancel: () -> Void

    /// A still waiting to be approved. Its presence is what shows the review.
    @State private var pending: CapturedCard?

    var body: some View {
        ZStack {
            camera
                .opacity(pending == nil ? 1 : 0)

            if let pending {
                ScanReviewScreen(
                    capture: pending,
                    onUse: onScan,
                    onRetake: { self.pending = nil }
                )
                .transition(.opacity)
            }
        }
        .animation(Motion.snappy, value: pending == nil)
        .background(Palette.scanBackdrop.ignoresSafeArea())
    }

    @ViewBuilder
    private var camera: some View {
        #if targetEnvironment(simulator) && DEBUG
        SimulatedCaptureView(onCapture: { pending = $0 }, onCancel: onCancel)
        #else
        switch ScanSource.preferred {
        case .visionKit:
            VisionKitCaptureView(onCapture: { pending = $0 }, onCancel: onCancel)
        case .camera:
            CameraCaptureView(
                onCapture: { pending = $0 },
                onCancel: onCancel,
                isActive: pending == nil
            )
        }
        #endif
    }
}

#if targetEnvironment(simulator) && DEBUG
/// There is no camera in the simulator, so this stands in for one: it returns a
/// bundled sample as though it had just been scanned. Debug builds only.
struct SimulatedCaptureView: View {
    let onCapture: (CapturedCard) -> Void
    let onCancel: () -> Void

    /// Nil is a card from the bundled archive.
    @State private var demo: DemoScan? = DemoScan.requested

    var body: some View {
        ZStack {
            Palette.scanBackdrop.ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "camera.metering.unknown")
                    .font(.system(size: 34, weight: .light))
                Text("No camera in the simulator")
                    .font(Typography.coaching)
                Text("Capture returns the chosen sample on a surface")
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

                HStack(spacing: 8) {
                    demoChoice("Archive", nil)
                    ForEach(DemoScan.allCases) { kind in
                        demoChoice(kind.title, kind)
                    }
                }
                .padding(.bottom, 24)

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
            if DebugHooks.opensReview { shoot() }
        }
    }

    private func demoChoice(_ title: String, _ kind: DemoScan?) -> some View {
        let isOn = demo == kind
        return Button {
            demo = kind
        } label: {
            Text(title)
                .font(Typography.subtitle)
                .foregroundStyle(isOn ? Palette.scanBackdrop : .white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(isOn ? .white : .white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func shoot() {
        let captured = if let demo { demo.capture() } else { SampleArchive.sampleCapture() }
        guard let captured else {
            onCancel()
            return
        }
        onCapture(captured)
    }
}
#endif
