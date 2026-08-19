import BackendRegistry
import Domain
import Foundation

public enum ArchiveModification: Hashable, Sendable {
    case add([URL])
    case remove(entryIDs: Set<ArchiveEntry.ID>)
    case replace(entryID: ArchiveEntry.ID, with: URL)
}

public struct ModifyArchiveRequest: Sendable {
    public let archiveURL: URL
    public let changes: [ArchiveModification]
    public init(archiveURL: URL, changes: [ArchiveModification]) { self.archiveURL = archiveURL; self.changes = changes }
}

public struct ModifyArchiveUseCase: Sendable {
    private let registry: ArchiveBackendRegistry
    public init(registry: ArchiveBackendRegistry) { self.registry = registry }

    public func execute(_ request: ModifyArchiveRequest) async throws -> Never {
        do {
            _ = try await registry.detectAndSelect(for: request.archiveURL, operation: .modify)
            throw ApplicationError(.unsupportedOperation,
                                   message: "Rebuild modification is not available until a streaming retained-entry writer is implemented",
                                   diagnosticCode: "REBUILD_PIPELINE_UNAVAILABLE")
        } catch { throw ApplicationError.map(error) }
    }
}
