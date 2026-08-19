import ArchiveSecurity
import BackendProtocol
import BackendRegistry
import CrashSafeFilesystem
import Domain
import Foundation

public struct PreviewRequest: Sendable {
    public let archiveURL: URL
    public let entry: ArchiveEntry
    public let credential: ArchiveCredential?
    public let maximumPreviewBytes: UInt64
    public init(archiveURL: URL, entry: ArchiveEntry, credential: ArchiveCredential? = nil,
                maximumPreviewBytes: UInt64 = 256 * 1_024 * 1_024) {
        self.archiveURL = archiveURL; self.entry = entry; self.credential = credential
        self.maximumPreviewBytes = maximumPreviewBytes
    }
}

public final class PreviewArtifact: @unchecked Sendable {
    public let fileURL: URL
    public let warning: ArchiveWarning?
    private let rootURL: URL
    private let lock = NSLock()
    private var cleaned = false

    init(fileURL: URL, rootURL: URL, warning: ArchiveWarning?) {
        self.fileURL = fileURL; self.rootURL = rootURL; self.warning = warning
    }
    public func cleanup() {
        lock.lock(); defer { lock.unlock() }
        guard !cleaned else { return }; cleaned = true
        try? FileManager.default.removeItem(at: rootURL)
    }
    deinit { cleanup() }
}

public struct PreviewUseCase: Sendable {
    private let registry: ArchiveBackendRegistry
    private let filesystem: CrashSafeFilesystem
    public init(registry: ArchiveBackendRegistry, filesystem: CrashSafeFilesystem) {
        self.registry = registry; self.filesystem = filesystem
    }

    public func execute(_ request: PreviewRequest) async throws -> PreviewArtifact {
        guard request.entry.kind == .regularFile else {
            throw ApplicationError(.unsupportedOperation, message: "Only regular files can be previewed",
                                   diagnosticCode: "PREVIEW_ENTRY_TYPE")
        }
        if let size = request.entry.uncompressedSize, size > request.maximumPreviewBytes {
            throw ApplicationError(.insufficientSpace, message: "The entry exceeds the preview size limit",
                                   diagnosticCode: "PREVIEW_SIZE_LIMIT")
        }
        do {
            let (_, selection) = try await registry.detectAndSelect(for: request.archiveURL, operation: .extract)
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("archivist-preview", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            do {
                let plan = try SecureExtractionPlanner().plan(destinationRoot: root, entries: [request.entry])
                guard let destination = plan.first?.destinationURL else {
                    throw ApplicationError(.unsafeArchiveEntry, message: "Preview path could not be validated",
                                           diagnosticCode: "PREVIEW_PATH_REJECTED")
                }
                let options = ExtractionOptions(conflictResolution: .replace, credential: request.credential)
                let extraction = ExtractionUseCase(registry: registry, filesystem: filesystem).execute(
                    .init(archiveURL: request.archiveURL, selectedEntryIDs: [request.entry.id],
                          destinationURL: root, options: options))
                for try await _ in extraction { try Task.checkCancellation() }
                let warning: ArchiveWarning? = selection.capabilities.requiresSequentialScan
                    ? .init(.integrityDetailUnavailable,
                            message: "This format requires sequential scanning; the backend may read the full archive to preview one entry.",
                            backendIdentifier: selection.backend.identifier.rawValue)
                    : nil
                return PreviewArtifact(fileURL: destination, rootURL: root, warning: warning)
            } catch {
                try? FileManager.default.removeItem(at: root); throw error
            }
        } catch { throw ApplicationError.map(error) }
    }
}
