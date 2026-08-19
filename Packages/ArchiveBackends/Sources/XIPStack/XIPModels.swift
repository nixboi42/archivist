import Foundation
import Domain

public enum IntegrityStatus: String, Codable, Hashable, Sendable { case valid, invalid, notChecked, unavailable }
public enum SignatureStatus: String, Codable, Hashable, Sendable { case validBySystemXIP, invalid, notPresent, notChecked, unavailable }
public enum TrustStatus: String, Codable, Hashable, Sendable { case trustedBySystemXIPPolicy, untrusted, notIndependentlyEvaluated, unavailable }
public enum XIPPayloadKind: String, Codable, Hashable, Sendable { case appleArchive, legacyPBZX, unknown }

public struct XIPVerificationResult: Codable, Hashable, Sendable {
    public let containerStructure: IntegrityStatus
    public let containerChecksum: IntegrityStatus
    public let cryptographicSignature: SignatureStatus
    public let signerTrust: TrustStatus
    public let payloadIntegrity: IntegrityStatus?
    public init(containerStructure: IntegrityStatus, containerChecksum: IntegrityStatus,
                cryptographicSignature: SignatureStatus, signerTrust: TrustStatus,
                payloadIntegrity: IntegrityStatus?) {
        self.containerStructure=containerStructure;self.containerChecksum=containerChecksum
        self.cryptographicSignature=cryptographicSignature;self.signerTrust=signerTrust;self.payloadIntegrity=payloadIntegrity
    }
}

public extension XIPVerificationResult {
    var domainDetails: ArchiveVerificationDetails {
        .xip(.init(containerStructure: .init(rawValue: containerStructure.rawValue)!,
                   containerChecksum: .init(rawValue: containerChecksum.rawValue)!,
                   cryptographicSignature: .init(rawValue: cryptographicSignature.rawValue)!,
                   signerTrust: .init(rawValue: signerTrust.rawValue)!,
                   payloadIntegrity: payloadIntegrity.flatMap { .init(rawValue: $0.rawValue) }))
    }
}

public enum XIPStackError: Error, Equatable, Sendable {
    case notXAR, malformedXAR(String), resourceLimitExceeded, unsupportedLegacyPayload, unsupportedPayload
    case systemToolFailure(tool: String, status: Int32, message: String)
    case appleArchiveFailure(String)
}

public struct XAREntry: Codable, Hashable, Sendable {
    public let path: String; public let kind: String?; public let size: UInt64?
}
public struct XARInspectionResult: Codable, Hashable, Sendable {
    public let headerSize: UInt16; public let version: UInt16; public let tocCompressedSize: UInt64
    public let tocUncompressedSize: UInt64; public let checksumAlgorithm: UInt32; public let entries: [XAREntry]
    public var hasXIPShape: Bool { let names=Set(entries.map(\.path));return names.contains("Content") && names.contains("Metadata") }
    public init(headerSize:UInt16,version:UInt16,tocCompressedSize:UInt64,tocUncompressedSize:UInt64,checksumAlgorithm:UInt32,entries:[XAREntry]){self.headerSize=headerSize;self.version=version;self.tocCompressedSize=tocCompressedSize;self.tocUncompressedSize=tocUncompressedSize;self.checksumAlgorithm=checksumAlgorithm;self.entries=entries}
}

public struct XIPInspection: Sendable {
    public let container: XARInspectionResult
    public let payloadKind: XIPPayloadKind
    public let payloadEntries: [AppleArchiveEntry]
    public let verification: XIPVerificationResult
    public init(container:XARInspectionResult,payloadKind:XIPPayloadKind,payloadEntries:[AppleArchiveEntry],verification:XIPVerificationResult){self.container=container;self.payloadKind=payloadKind;self.payloadEntries=payloadEntries;self.verification=verification}
}

public struct AppleArchiveEntry: Codable, Hashable, Sendable {
    public let path: String
    public let typeDescription: String
}
