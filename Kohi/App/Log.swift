import os

/// One logger for the whole app. Small enough that subsystems would be noise.
nonisolated enum Log {
    static let app = Logger(subsystem: "studio.jbk.Kohi", category: "kohi")
}
