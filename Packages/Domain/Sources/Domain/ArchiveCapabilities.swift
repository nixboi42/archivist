public struct ArchiveCapabilities: Codable, Hashable, Sendable {
    public let operations: Set<ArchiveOperation>
    public let encryptionRead: EncryptionSupport?
    public let encryptionCreate: EncryptionSupport?
    public let supportsSolidArchives: Bool
    public let supportsMultiVolume: Bool
    public let supportsUnixMetadata: Bool
    public let supportsExtendedAttributes: Bool
    public let supportsRandomAccess: Bool
    public let requiresSequentialScan: Bool
    public let creationOptions: CreationOptionCapabilities?

    public init(operations: Set<ArchiveOperation> = [], encryptionRead: EncryptionSupport? = nil,
                encryptionCreate: EncryptionSupport? = nil, supportsSolidArchives: Bool = false,
                supportsMultiVolume: Bool = false, supportsUnixMetadata: Bool = false,
                supportsExtendedAttributes: Bool = false, supportsRandomAccess: Bool = false,
                requiresSequentialScan: Bool = false, creationOptions: CreationOptionCapabilities? = nil) {
        self.operations = operations
        self.encryptionRead = encryptionRead
        self.encryptionCreate = encryptionCreate
        self.supportsSolidArchives = supportsSolidArchives
        self.supportsMultiVolume = supportsMultiVolume
        self.supportsUnixMetadata = supportsUnixMetadata
        self.supportsExtendedAttributes = supportsExtendedAttributes
        self.supportsRandomAccess = supportsRandomAccess
        self.requiresSequentialScan = requiresSequentialScan
        self.creationOptions = creationOptions
    }

    public func supports(_ operation: ArchiveOperation) -> Bool { operations.contains(operation) }
    public static let unsupported = ArchiveCapabilities()
}
