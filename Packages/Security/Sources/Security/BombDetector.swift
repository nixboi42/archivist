import Domain

public struct ArchiveSizeSummary: Codable, Hashable, Sendable {
    public let entryCount: UInt64?
    public let uncompressedBytes: UInt64?
    public let compressedBytes: UInt64?
    public init(entryCount: UInt64? = nil, uncompressedBytes: UInt64? = nil, compressedBytes: UInt64? = nil) {
        self.entryCount = entryCount; self.uncompressedBytes = uncompressedBytes; self.compressedBytes = compressedBytes
    }
}

public struct BombDetector: Sendable {
    public struct State: Codable, Hashable, Sendable {
        fileprivate var entries: UInt64 = 0, declaredBytes: UInt64 = 0, producedBytes: UInt64 = 0, compressedBytes: UInt64 = 0
        public init() {}
    }
    public let limits: SecurityPolicy.ResourceLimits
    public init(limits: SecurityPolicy.ResourceLimits) { self.limits = limits }

    public func preflight(_ summary: ArchiveSizeSummary, resources: ResourceSnapshot = .init()) throws {
        if let count = summary.entryCount, count > limits.maximumEntries { throw ArchiveSecurityError(.entryCountLimitExceeded, level: .policy) }
        if let size = summary.uncompressedBytes, size > limits.maximumExpandedBytes { throw ArchiveSecurityError(.decompressedSizeLimitExceeded, level: .policy) }
        try checkRatio(uncompressed: summary.uncompressedBytes, compressed: summary.compressedBytes)
        if case .insufficient = ResourceLimiter().assess(requiredOutputBytes: summary.uncompressedBytes, resources: resources) {
            throw ArchiveSecurityError(.insufficientDiskSpace, level: .policy)
        }
    }

    public func observeEntry(state: inout State, uncompressedBytes: UInt64?, compressedBytes: UInt64?) throws {
        state.entries += 1
        if state.entries > limits.maximumEntries { throw ArchiveSecurityError(.entryCountLimitExceeded, level: .policy) }
        if let value = uncompressedBytes {
            let (sum, overflow) = state.declaredBytes.addingReportingOverflow(value); state.declaredBytes = sum
            if overflow || sum > limits.maximumExpandedBytes { throw ArchiveSecurityError(.decompressedSizeLimitExceeded, level: .policy) }
        }
        if let value = compressedBytes { state.compressedBytes = state.compressedBytes.addingReportingOverflow(value).partialValue }
        try checkRatio(uncompressed: uncompressedBytes, compressed: compressedBytes)
        try checkRatio(uncompressed: state.declaredBytes, compressed: state.compressedBytes == 0 ? nil : state.compressedBytes)
    }

    // Invariant D: streamed output is counted, not retained.
    public func observeProducedBytes(_ count: UInt64, state: inout State) throws {
        let (sum, overflow) = state.producedBytes.addingReportingOverflow(count); state.producedBytes = sum
        if overflow || sum > limits.maximumExpandedBytes { throw ArchiveSecurityError(.decompressedSizeLimitExceeded, level: .policy) }
    }

    private func checkRatio(uncompressed: UInt64?, compressed: UInt64?) throws {
        guard let uncompressed, let compressed, compressed > 0,
              Double(uncompressed) / Double(compressed) > limits.maximumCompressionRatio else { return }
        throw ArchiveSecurityError(.suspiciousCompressionRatio, level: .policy)
    }
}
