import Foundation
import os.log

enum DebugLog {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.danielvanacker.MusicSync", category: "app")

    static func log(_ message: String) {
        let line = "[MusicSync] \(message)"
        logger.info("\(line, privacy: .public)")
        print(line)
    }

    static func error(_ message: String) {
        let line = "[MusicSync] ❌ \(message)"
        logger.error("\(line, privacy: .public)")
        print(line)
    }
}
