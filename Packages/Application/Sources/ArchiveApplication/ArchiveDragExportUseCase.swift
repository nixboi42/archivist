import BackendProtocol
import BackendRegistry
import ArchiveSecurity
import CrashSafeFilesystem
import Domain
import Foundation

public struct ArchiveDragExportRequest: Sendable {
    public let archiveURL: URL
    public let selectedEntryIDs: Set<ArchiveEntry.ID>
    public let credential: ArchiveCredential?
    public let securityPolicy: SecurityPolicy

    public init(archiveURL: URL, selectedEntryIDs: Set<ArchiveEntry.ID>,
                credential: ArchiveCredential? = nil,
                securityPolicy: SecurityPolicy = .secureDefault) {
        self.archiveURL = archiveURL
        self.selectedEntryIDs = selectedEntryIDs
        self.credential = credential
        self.securityPolicy = securityPolicy
    }
}

public struct ArchiveDragExportSelection: Equatable, Sendable {
    public let roots: [ArchiveEntry]
    public let entries: [ArchiveEntry]

    public static func resolve(selectedIDs: Set<ArchiveEntry.ID>, in entries: [ArchiveEntry]) throws -> Self {
        let selected = entries.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else {
            throw ApplicationError(.unsupportedOperation, message: "No archive entries are selected",
                                   diagnosticCode: "DRAG_EXPORT_EMPTY_SELECTION")
        }
        let ordered = selected.sorted { lhs, rhs in
            let ld = lhs.path.split(separator: "/").count, rd = rhs.path.split(separator: "/").count
            return ld == rd ? lhs.path < rhs.path : ld < rd
        }
        var roots: [ArchiveEntry] = []
        for entry in ordered {
            let redundant = roots.contains { root in
                root.kind == .directory && Self.isDescendant(entry.path, of: root.path)
            }
            if !redundant { roots.append(entry) }
        }
        let included = entries.filter { entry in
            roots.contains { root in entry.id == root.id || (root.kind == .directory && Self.isDescendant(entry.path, of: root.path)) }
        }
        return .init(roots: roots, entries: included)
    }

    private static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        let prefix = ancestor.hasSuffix("/") ? ancestor : ancestor + "/"
        return path.hasPrefix(prefix) && path != ancestor
    }
}

public final class ArchiveDragExportArtifact: @unchecked Sendable {
    public let rootURL: URL
    public let promisedURLsByEntryID: [ArchiveEntry.ID: URL]
    private let lock = NSLock()
    private var cleaned = false

    init(rootURL: URL, promisedURLsByEntryID: [ArchiveEntry.ID: URL]) {
        self.rootURL = rootURL; self.promisedURLsByEntryID = promisedURLsByEntryID
    }

    public func cleanup() {
        lock.lock(); defer { lock.unlock() }
        guard !cleaned else { return }
        cleaned = true
        try? FileManager.default.removeItem(at: rootURL)
    }

    deinit { cleanup() }
}

public struct ArchiveDragExportUseCase: Sendable {
    public static let temporaryRootName = "com.keremgurevin.Archivist/DragExports"
    public static let orphanLifetime: TimeInterval = 24 * 60 * 60
    private let registry: ArchiveBackendRegistry
    private let filesystem: CrashSafeFilesystem

    public init(registry: ArchiveBackendRegistry, filesystem: CrashSafeFilesystem) {
        self.registry = registry; self.filesystem = filesystem
    }

    public func execute(_ request: ArchiveDragExportRequest,
                        onProgress: @escaping @Sendable (ProgressEvent) -> Void = { _ in }) async throws -> ArchiveDragExportArtifact {
        let operationRoot = Self.dragExportsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try Self.prepareRoot(operationRoot)
            let (detection, selection) = try await registry.detectAndSelect(for: request.archiveURL, operation: .extract)
            let handle = try await selection.backend.open(request.archiveURL, format: detection.format,
                                                            credential: request.credential)
            var allEntries: [ArchiveEntry] = []
            do {
                for try await entry in selection.backend.list(handle) {
                    try Task.checkCancellation(); allEntries.append(entry)
                }
                await selection.backend.close(handle)
            } catch {
                await selection.backend.close(handle); throw error
            }
            let resolved = try ArchiveDragExportSelection.resolve(selectedIDs: request.selectedEntryIDs, in: allEntries)
            let extraction = ExtractionUseCase(registry: registry, filesystem: filesystem).execute(
                .init(archiveURL: request.archiveURL,
                      selectedEntryIDs: Set(resolved.entries.map(\.id)),
                      destinationURL: operationRoot,
                      options: .init(conflictResolution: .replace, preserveMetadata: true,
                                     credential: request.credential, securityPolicy: request.securityPolicy)))
            for try await event in extraction { try Task.checkCancellation(); onProgress(event) }
            let planned = try SecureExtractionPlanner(policy: request.securityPolicy)
                .plan(destinationRoot: operationRoot, entries: resolved.entries)
            let byID = Dictionary(uniqueKeysWithValues: planned.map { ($0.entry.id, $0.destinationURL) })
            let promised = Dictionary(uniqueKeysWithValues: try resolved.roots.map { root in
                guard let url = byID[root.id], FileManager.default.fileExists(atPath: url.path) else {
                    throw ApplicationError(.backendFailure, message: "A promised archive item was not materialized",
                                           diagnosticCode: "DRAG_EXPORT_MISSING_ITEM")
                }
                return (root.id, url)
            })
            return .init(rootURL: operationRoot, promisedURLsByEntryID: promised)
        } catch {
            try? FileManager.default.removeItem(at: operationRoot)
            throw ApplicationError.map(error)
        }
    }

    public static func sweepOrphans(now: Date = Date(), fileManager: FileManager = .default) {
        guard let children = try? fileManager.contentsOfDirectory(at: dragExportsRoot,
                                                                  includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]) else { return }
        for child in children {
            guard let values = try? child.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  values.isDirectory == true, let date = values.contentModificationDate,
                  now.timeIntervalSince(date) > orphanLifetime else { continue }
            try? fileManager.removeItem(at: child)
        }
    }

    public static var dragExportsRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(temporaryRootName, isDirectory: true)
    }

    private static func prepareRoot(_ root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }
}
