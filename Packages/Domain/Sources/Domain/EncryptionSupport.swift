public enum EncryptionAlgorithm: String, Codable, CaseIterable, Hashable, Sendable {
    case zipCrypto, aes128, aes192, aes256, sevenZipAES256
}

public struct EncryptionSupport: Codable, Hashable, Sendable {
    public let algorithms: Set<EncryptionAlgorithm>
    public let supportsHeaderEncryption: Bool

    public init(algorithms: Set<EncryptionAlgorithm>, supportsHeaderEncryption: Bool = false) {
        self.algorithms = algorithms
        self.supportsHeaderEncryption = supportsHeaderEncryption
    }
}
