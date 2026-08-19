public struct SecurityPolicy: Codable, Hashable, Sendable {
    public struct ResourceLimits: Codable, Hashable, Sendable {
        public static let hardMaximumEntries: UInt64 = 10_000_000
        public static let hardMaximumExpandedBytes: UInt64 = 16 * 1_024 * 1_024 * 1_024 * 1_024
        public static let hardMaximumCompressionRatio: Double = 1_000_000

        public let maximumEntries: UInt64
        public let maximumExpandedBytes: UInt64
        public let maximumCompressionRatio: Double

        public init(maximumEntries: UInt64 = 1_000_000,
                    maximumExpandedBytes: UInt64 = 1_024 * 1_024 * 1_024 * 1_024,
                    maximumCompressionRatio: Double = 100_000) {
            self.maximumEntries = min(max(maximumEntries, 1), Self.hardMaximumEntries)
            self.maximumExpandedBytes = min(max(maximumExpandedBytes, 1), Self.hardMaximumExpandedBytes)
            self.maximumCompressionRatio = min(max(maximumCompressionRatio, 1), Self.hardMaximumCompressionRatio)
        }
    }

    public let preventPathTraversal: Bool
    public let restrictUnsafeSymlinks: Bool
    public let restrictUnsafeHardlinks: Bool
    public let rejectUnicodeCollisions: Bool
    public let rejectMalformedStructures: Bool
    public let resourceLimits: ResourceLimits

    public init(preventPathTraversal: Bool = true, restrictUnsafeSymlinks: Bool = true,
                restrictUnsafeHardlinks: Bool = true, rejectUnicodeCollisions: Bool = true,
                rejectMalformedStructures: Bool = true, resourceLimits: ResourceLimits = .init()) {
        self.preventPathTraversal = preventPathTraversal
        self.restrictUnsafeSymlinks = restrictUnsafeSymlinks
        self.restrictUnsafeHardlinks = restrictUnsafeHardlinks
        self.rejectUnicodeCollisions = rejectUnicodeCollisions
        self.rejectMalformedStructures = rejectMalformedStructures
        self.resourceLimits = resourceLimits
    }

    public static let secureDefault = SecurityPolicy()
}
