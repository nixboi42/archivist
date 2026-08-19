public struct ArchiveWarning: Codable, Hashable, Sendable {
    public enum Code: String, Codable, Hashable, Sendable {
        case backendWarning
        case metadataPartiallyPreserved
        case integrityDetailUnavailable
    }

    public let code: Code
    public let message: String
    public let backendIdentifier: String?
    public let diagnosticCode: String?

    public init(_ code: Code, message: String, backendIdentifier: String? = nil, diagnosticCode: String? = nil) {
        self.code = code
        self.message = message
        self.backendIdentifier = backendIdentifier
        self.diagnosticCode = diagnosticCode
    }
}

public struct XIPVerificationDetails: Codable, Hashable, Sendable {
    public enum Integrity: String, Codable, Hashable, Sendable { case valid, invalid, notChecked, unavailable }
    public enum Signature: String, Codable, Hashable, Sendable { case validBySystemXIP, invalid, notPresent, notChecked, unavailable }
    public enum Trust: String, Codable, Hashable, Sendable { case trustedBySystemXIPPolicy, untrusted, notIndependentlyEvaluated, unavailable }

    public let containerStructure: Integrity
    public let containerChecksum: Integrity
    public let cryptographicSignature: Signature
    public let signerTrust: Trust
    public let payloadIntegrity: Integrity?

    public init(containerStructure: Integrity, containerChecksum: Integrity, cryptographicSignature: Signature,
                signerTrust: Trust, payloadIntegrity: Integrity?) {
        self.containerStructure = containerStructure; self.containerChecksum = containerChecksum
        self.cryptographicSignature = cryptographicSignature; self.signerTrust = signerTrust
        self.payloadIntegrity = payloadIntegrity
    }
}

public enum ArchiveVerificationDetails: Codable, Hashable, Sendable {
    case xip(XIPVerificationDetails)
}
