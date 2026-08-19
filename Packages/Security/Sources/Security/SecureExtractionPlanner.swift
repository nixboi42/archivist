import Domain
import Foundation

public struct ValidatedExtractionEntry: Codable, Hashable, Sendable {
    public let entry: ArchiveEntry
    public let relativePath: ValidatedRelativePath
    public let destinationURL: URL
    public let symlinkTarget: ValidatedLinkTarget?
    public let hardlink: HardlinkDecision?
}

public struct SecureExtractionPlanner: Sendable {
    public let policy: SecurityPolicy
    private let paths = PathValidator(), unicode = UnicodeNormalizer()
    public init(policy: SecurityPolicy = .secureDefault) { self.policy = policy }

    public func plan(destinationRoot: URL, entries: [ArchiveEntry], resources: ResourceSnapshot = .init()) throws -> [ValidatedExtractionEntry] {
        let detector = BombDetector(limits: policy.resourceLimits)
        try detector.preflight(.init(entryCount: UInt64(entries.count), uncompressedBytes: entries.compactMap(\.uncompressedSize).reduce(0, +),
                                     compressedBytes: entries.compactMap(\.compressedSize).reduce(0, +)), resources: resources)
        var collision = UnicodeCollisionTracker(), known = Set<ValidatedRelativePath>(), output: [ValidatedExtractionEntry] = []
        for entry in entries {
            let relative = unicode.normalize(try paths.validate(entry.path, policy: policy))
            try collision.insert(original: entry.path, normalized: relative)
            let symlink = entry.kind == .symbolicLink ? try entry.linkTarget.map { try SymlinkPolicy().validate(target: $0, symlinkPath: relative, policy: policy) } : nil
            let hardlink = entry.kind == .hardLink ? try entry.linkTarget.map { try HardlinkPolicy().validate(target: $0, knownPaths: known, policy: policy) } : nil
            output.append(.init(entry: entry, relativePath: relative, destinationURL: relative.appending(to: destinationRoot), symlinkTarget: symlink, hardlink: hardlink))
            known.insert(relative)
        }
        return output
    }
}
