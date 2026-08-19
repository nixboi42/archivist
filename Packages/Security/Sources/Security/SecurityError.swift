public enum SecurityRejectionLevel: String, Codable, Hashable, Sendable { case hardSafety, policy }

public struct ArchiveSecurityError: Error, Codable, Hashable, Sendable {
    public enum Code: String, Codable, Hashable, Sendable {
        case pathTraversal, absolutePath, invalidPath, unicodeCollision, unsafeSymlink, unsafeHardlink,
             entryCountLimitExceeded, decompressedSizeLimitExceeded, suspiciousCompressionRatio,
             insufficientDiskSpace, malformedMetadata
    }
    public let code: Code
    public let level: SecurityRejectionLevel
    public let entryPath: String?
    public init(_ code: Code, level: SecurityRejectionLevel, entryPath: String? = nil) {
        self.code = code; self.level = level; self.entryPath = entryPath
    }
}
