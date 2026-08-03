import CoreMotion
import Observation

/// How far the phone is tilted from however you were holding it when you opened
/// the card, as two numbers in -1...1.
///
/// Relative rather than absolute on purpose: the effect should start from rest
/// whether you are sitting upright at a table or lying down, so the first
/// reading becomes the origin and everything after is measured against it.
@Observable
final class DeviceTilt {
    /// Side to side. Positive is the right edge going away from you.
    private(set) var roll: Double = 0
    /// Front to back. Positive is the top edge going away from you.
    private(set) var pitch: Double = 0

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var reference: CMAttitude?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = Motion.Parallax.updateInterval
        // `xArbitraryZVertical` keeps the reference frame from chasing magnetic
        // north, which would make the card drift while the phone sits still.
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            apply(motion.attitude)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        reference = nil
        roll = 0
        pitch = 0
    }

    private func apply(_ attitude: CMAttitude) {
        guard let reference else {
            // `multiply(byInverseOf:)` mutates, so the origin has to be a copy.
            self.reference = attitude.copy() as? CMAttitude
            return
        }

        let relative = attitude.copy() as! CMAttitude
        relative.multiply(byInverseOf: reference)

        let range = Motion.Parallax.range
        let smoothing = Motion.Parallax.smoothing
        let targetRoll = min(max(relative.roll / range, -1), 1)
        let targetPitch = min(max(relative.pitch / range, -1), 1)

        // Device motion is noisy at rest; without this the card jitters while
        // the phone is flat on a table.
        roll += (targetRoll - roll) * smoothing
        pitch += (targetPitch - pitch) * smoothing
    }
}
