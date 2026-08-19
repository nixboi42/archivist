import Foundation

public struct UnicodeNormalizer: Sendable {
    public init() {}
    public func normalize(_ path: ValidatedRelativePath) -> ValidatedRelativePath {
        .init(components: path.components.map(\.precomposedStringWithCanonicalMapping))
    }
}

public struct UnicodeCollisionTracker: Sendable {
    private var originalsByNormalizedPath: [String: [UInt8]] = [:]
    public init() {}
    public mutating func insert(original: String, normalized: ValidatedRelativePath) throws {
        let key = normalized.string
        let originalBytes = Array(original.utf8)
        if let existing = originalsByNormalizedPath[key], existing != originalBytes {
            throw ArchiveSecurityError(.unicodeCollision, level: .policy, entryPath: original)
        }
        originalsByNormalizedPath[key] = originalBytes
    }
}
