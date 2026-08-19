import Foundation
import OSLog

enum StartupAccessAudit {
    private static let logger = Logger(subsystem: "com.keremgurevin.Archivist", category: "StartupAccess")

    static func event(_ category: String, _ detail: String) {
        #if DEBUG
        logger.info("[\(category, privacy: .public)] \(detail, privacy: .public)")
        #endif
    }

    static func path(_ category: String, _ url: URL, reason: String) {
        #if DEBUG
        logger.info("[\(category, privacy: .public)] path=\(url.path, privacy: .public) reason=\(reason, privacy: .public)")
        #endif
    }
}
