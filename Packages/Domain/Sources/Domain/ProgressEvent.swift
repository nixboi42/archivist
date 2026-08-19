public struct ProgressEvent: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, Hashable, Sendable { case preparing, listing, extracting, creating, testing, validating, finalizing }
    public let phase: Phase
    public let completedUnits: UInt64
    public let totalUnits: UInt64?
    public let currentEntryPath: String?
    public let bytesPerSecond: UInt64?
    public let warning: String?

    public init(phase: Phase, completedUnits: UInt64, totalUnits: UInt64? = nil,
                currentEntryPath: String? = nil, bytesPerSecond: UInt64? = nil, warning: String? = nil) {
        self.phase = phase
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.currentEntryPath = currentEntryPath
        self.bytesPerSecond = bytesPerSecond
        self.warning = warning
    }

    public var fractionCompleted: Double? {
        guard let totalUnits, totalUnits > 0 else { return nil }
        return min(Double(completedUnits) / Double(totalUnits), 1)
    }
}
