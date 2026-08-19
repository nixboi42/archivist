import BackendProtocol
import Domain
import Foundation

public struct BrowseRequest: Sendable {
    public let archiveURL: URL
    public let credential: ArchiveCredential?
    public init(archiveURL: URL, credential: ArchiveCredential? = nil) { self.archiveURL = archiveURL; self.credential = credential }
}

public struct ExtractionRequest: Sendable {
    public let archiveURL: URL
    public let selectedEntryIDs: Set<ArchiveEntry.ID>?
    public let destinationURL: URL
    public let options: ExtractionOptions
    public init(archiveURL: URL, selectedEntryIDs: Set<ArchiveEntry.ID>? = nil, destinationURL: URL,
                options: ExtractionOptions = .init()) {
        self.archiveURL = archiveURL; self.selectedEntryIDs = selectedEntryIDs
        self.destinationURL = destinationURL; self.options = options
    }
}

public extension ExtractionRequest {
    /// Returns the same logical extraction request with only its backend credential changed.
    /// Credential retries must not reconstruct extraction policy from defaults.
    func withCredential(_ credential: ArchiveCredential) -> ExtractionRequest {
        ExtractionRequest(
            archiveURL: archiveURL,
            selectedEntryIDs: selectedEntryIDs,
            destinationURL: destinationURL,
            options: ExtractionOptions(
                conflictResolution: options.conflictResolution,
                preserveMetadata: options.preserveMetadata,
                credential: credential,
                securityPolicy: options.securityPolicy
            )
        )
    }
}

public struct CreationRequest: Sendable {
    public let sourceURLs: [URL]
    public let destinationURL: URL
    public let options: CreationOptions
    public let overwritePolicy: ConflictResolution
    public init(sourceURLs: [URL], destinationURL: URL, options: CreationOptions,
                overwritePolicy: ConflictResolution = .ask) {
        self.sourceURLs = sourceURLs; self.destinationURL = destinationURL
        self.options = options; self.overwritePolicy = overwritePolicy
    }
}

public struct TestArchiveResult: Hashable, Sendable {
    public let format: ArchiveFormat
    public let backendIdentifier: BackendIdentifier
    public let warnings: [ArchiveWarning]
    public let details: ArchiveVerificationDetails?
    public init(format: ArchiveFormat, backendIdentifier: BackendIdentifier, warnings: [ArchiveWarning],
                details: ArchiveVerificationDetails? = nil) {
        self.format = format; self.backendIdentifier = backendIdentifier; self.warnings = warnings; self.details = details
    }
}

public struct ConflictContext: Sendable {
    public let destinationURL: URL
    public let entry: ArchiveEntry?
    public init(destinationURL: URL, entry: ArchiveEntry?) { self.destinationURL = destinationURL; self.entry = entry }
}

public struct ConflictDecision: Sendable {
    public let resolution: ConflictResolution
    public let scope: ConflictScope
    public init(_ resolution: ConflictResolution, scope: ConflictScope = .singleEntry) {
        self.resolution = resolution; self.scope = scope
    }
}

public protocol ConflictResolving: Sendable {
    func resolve(_ context: ConflictContext) async throws -> ConflictDecision
}

public struct RejectingConflictResolver: ConflictResolving {
    public init() {}
    public func resolve(_ context: ConflictContext) async throws -> ConflictDecision {
        throw ApplicationError(.filesystemFailure, message: "Conflict requires a decision for \(context.destinationURL.path)",
                               diagnosticCode: "CONFLICT_DECISION_REQUIRED")
    }
}
