import Domain

public struct ResourceSnapshot: Codable, Hashable, Sendable {
    public let availableDiskBytes: UInt64?
    public let temporaryOverheadBytes: UInt64
    public init(availableDiskBytes: UInt64? = nil, temporaryOverheadBytes: UInt64 = 0) {
        self.availableDiskBytes = availableDiskBytes; self.temporaryOverheadBytes = temporaryOverheadBytes
    }
}

public enum DiskSpaceAssessment: Codable, Hashable, Sendable { case sufficient, insufficient(required: UInt64, available: UInt64), unknown }

public struct ResourceLimiter: Sendable {
    public init() {}
    public func assess(requiredOutputBytes: UInt64?, resources: ResourceSnapshot) -> DiskSpaceAssessment {
        guard let requiredOutputBytes, let available = resources.availableDiskBytes else { return .unknown }
        let (required, overflow) = requiredOutputBytes.addingReportingOverflow(resources.temporaryOverheadBytes)
        guard !overflow else { return .insufficient(required: .max, available: available) }
        return available >= required ? .sufficient : .insufficient(required: required, available: available)
    }
}
