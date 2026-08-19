import Domain
import Foundation

public struct BackendIdentifier: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct ArchiveHandle: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let backend: BackendIdentifier
    public let format: ArchiveFormat
    public init(id: UUID = UUID(), backend: BackendIdentifier, format: ArchiveFormat) {
        self.id = id; self.backend = backend; self.format = format
    }
}

public struct ArchiveCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let password: String
    public init(password: String) { self.password = password }
    public var description: String { "<redacted>" }
    public var debugDescription: String { "ArchiveCredential(<redacted>)" }
}

public struct ExtractionOptions: Sendable {
    public let conflictResolution: ConflictResolution
    public let preserveMetadata: Bool
    public let credential: ArchiveCredential?
    public let securityPolicy: SecurityPolicy
    public init(conflictResolution: ConflictResolution = .ask, preserveMetadata: Bool = true, credential: ArchiveCredential? = nil,
                securityPolicy: SecurityPolicy = .secureDefault) {
        self.conflictResolution = conflictResolution; self.preserveMetadata = preserveMetadata; self.credential = credential
        self.securityPolicy = securityPolicy
    }
}

public struct CreationOptions: Sendable {
    public let format: ArchiveFormat
    public let compressionLevel: CompressionLevel?
    public let method: CompressionMethod?
    public let dictionarySize: UInt64?
    public let wordSize: Int?
    public let solidMode: SolidMode
    public let threads: ThreadConfiguration
    public let encryptFileNames: Bool
    public let volumeSize: VolumeSize?
    public let credential: ArchiveCredential?
    public init(format: ArchiveFormat, compressionLevel: CompressionLevel? = nil,
                method: CompressionMethod? = nil, dictionarySize: UInt64? = nil, wordSize: Int? = nil,
                solidMode: SolidMode = .automatic, threads: ThreadConfiguration = .automatic,
                encryptFileNames: Bool = false, volumeSize: VolumeSize? = nil,
                credential: ArchiveCredential? = nil) {
        self.format = format; self.compressionLevel = compressionLevel; self.method = method
        self.dictionarySize = dictionarySize; self.wordSize = wordSize; self.solidMode = solidMode
        self.threads = threads; self.encryptFileNames = encryptFileNames; self.volumeSize = volumeSize
        self.credential = credential
    }

    /// Compatibility initializer for callers that still provide the former 0...9 model.
    public init(format: ArchiveFormat, compressionLevel: Int?, solid: Bool = false,
                credential: ArchiveCredential? = nil) {
        let level: CompressionLevel? = compressionLevel.map {
            switch $0 { case ...0: .store; case 1...2: .fastest; case 3...4: .fast
            case 5...6: .normal; case 7...8: .maximum; default: .ultra }
        }
        self.init(format: format, compressionLevel: level, solidMode: solid ? .on : .off,
                  credential: credential)
    }

    public var solid: Bool { solidMode == .on }
}

public enum CreationOptionsValidationError: Error, Equatable, Sendable {
    case unsupportedLevel, unsupportedMethod, unsupportedDictionary, unsupportedWordSize
    case unsupportedSolidMode, unsupportedThreads, threadCountOutOfRange
    case headerEncryptionRequiresPassword, unsupportedHeaderEncryption, unsupportedVolumes
}

public extension CreationOptions {
    func validate(against capabilities: CreationOptionCapabilities,
                  logicalProcessorCount: Int = ProcessInfo.processInfo.activeProcessorCount) throws {
        if let compressionLevel, !capabilities.compressionLevels.contains(compressionLevel) { throw CreationOptionsValidationError.unsupportedLevel }
        if let method, !capabilities.methods.contains(method) { throw CreationOptionsValidationError.unsupportedMethod }
        if let dictionarySize, !capabilities.dictionarySizes.contains(dictionarySize) { throw CreationOptionsValidationError.unsupportedDictionary }
        if let wordSize, !capabilities.wordSizes.contains(wordSize) { throw CreationOptionsValidationError.unsupportedWordSize }
        if solidMode != .automatic && !capabilities.supportsSolid { throw CreationOptionsValidationError.unsupportedSolidMode }
        if case .explicit(let count) = threads {
            guard capabilities.supportsThreadCount else { throw CreationOptionsValidationError.unsupportedThreads }
            guard count >= 1, count <= min(max(logicalProcessorCount, 1), 64) else { throw CreationOptionsValidationError.threadCountOutOfRange }
        }
        if encryptFileNames {
            guard credential != nil else { throw CreationOptionsValidationError.headerEncryptionRequiresPassword }
            guard capabilities.supportsHeaderEncryption else { throw CreationOptionsValidationError.unsupportedHeaderEncryption }
        }
        if volumeSize != nil && !capabilities.supportsVolumes { throw CreationOptionsValidationError.unsupportedVolumes }
        if dictionarySize != nil && method == .copy { throw CreationOptionsValidationError.unsupportedDictionary }
        if wordSize != nil && (method == .copy || method == .bzip2) { throw CreationOptionsValidationError.unsupportedWordSize }
        if dictionarySize != nil && method == .bzip2 { throw CreationOptionsValidationError.unsupportedDictionary }
    }
}

public protocol ArchiveBackend: Sendable {
    var identifier: BackendIdentifier { get }
    func capabilities(for format: ArchiveFormat) -> ArchiveCapabilities
    func open(_ url: URL, format: ArchiveFormat, credential: ArchiveCredential?) async throws -> ArchiveHandle
    func list(_ handle: ArchiveHandle) -> AsyncThrowingStream<ArchiveEntry, Error>
    func extract(_ handle: ArchiveHandle, entries: [ArchiveEntry]?, to destination: URL,
                 options: ExtractionOptions) -> AsyncThrowingStream<ProgressEvent, Error>
    func create(from sources: [URL], to destination: URL,
                options: CreationOptions) -> AsyncThrowingStream<ProgressEvent, Error>
    func test(_ handle: ArchiveHandle) -> AsyncThrowingStream<ProgressEvent, Error>
    func close(_ handle: ArchiveHandle) async
}

/// Optional richer verification channel. The base test stream remains unchanged for all backends.
public protocol DetailedVerificationProviding: ArchiveBackend {
    func verificationDetails(for handle: ArchiveHandle) async -> ArchiveVerificationDetails?
}

public extension ArchiveBackend {
    func requireOwnedHandle(_ handle: ArchiveHandle) throws {
        guard handle.backend == identifier else {
            throw ArchiveBackendError(.backendFailure, backendIdentifier: identifier.rawValue,
                                      message: "Archive handle belongs to another backend", diagnosticCode: "HANDLE_OWNER_MISMATCH")
        }
    }
}
