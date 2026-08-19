import ArchiveSecurity
import BackendProtocol
import BackendRegistry
import CrashSafeFilesystem
import Domain
import Foundation
import OSLog

public struct ExtractionUseCase: Sendable {
    private static let logger = Logger(subsystem: "com.keremgurevin.Archivist", category: "extraction-conflicts")
    private let registry: ArchiveBackendRegistry
    private let filesystem: CrashSafeFilesystem
    private let conflictResolver: any ConflictResolving

    public init(registry: ArchiveBackendRegistry, filesystem: CrashSafeFilesystem,
                conflictResolver: any ConflictResolving = RejectingConflictResolver()) {
        self.registry = registry; self.filesystem = filesystem; self.conflictResolver = conflictResolver
    }

    public func execute(_ request: ExtractionRequest) -> AsyncThrowingStream<ProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var handle: ArchiveHandle?
                var backend: (any ArchiveBackend)?
                var staging: URL?
                do {
                    Self.logger.notice("ExtractionUseCase entered; effectiveConflict=\(request.options.conflictResolution.rawValue, privacy: .public); destination=\(request.destinationURL.path, privacy: .private(mask: .hash))")
                    let (detection, selection) = try await registry.detectAndSelect(for: request.archiveURL, operation: .extract)
                    backend = selection.backend
                    let opened = try await selection.backend.open(request.archiveURL, format: detection.format,
                                                                    credential: request.options.credential)
                    handle = opened

                    var entries: [ArchiveEntry] = []
                    for try await entry in selection.backend.list(opened) {
                        try Task.checkCancellation()
                        if request.selectedEntryIDs == nil || request.selectedEntryIDs!.contains(entry.id) { entries.append(entry) }
                    }
                    let plans = try SecureExtractionPlanner(policy: request.options.securityPolicy)
                        .plan(destinationRoot: request.destinationURL, entries: entries)
                    let stage = try makeStagingDirectory(beside: request.destinationURL)
                    staging = stage
                    let stagingOptions = ExtractionOptions(conflictResolution: .replace,
                                                           preserveMetadata: false,
                                                           credential: request.options.credential,
                                                           securityPolicy: request.options.securityPolicy)
                    Self.logger.debug("backend extraction targets isolated empty staging; stagingConflict=replace; finalConflict=\(request.options.conflictResolution.rawValue, privacy: .public)")
                    for try await event in selection.backend.extract(opened, entries: entries, to: stage, options: stagingOptions) {
                        try Task.checkCancellation(); continuation.yield(event)
                    }

                    var remainingDecision: ConflictResolution?
                    for (index, plan) in plans.enumerated() {
                        try Task.checkCancellation()
                        let destination = try await resolvedDestination(for: plan, policy: request.options.conflictResolution,
                                                                        remaining: &remainingDecision)
                        guard let destination else { continue }
                        let source = plan.relativePath.appending(to: stage)
                        try await materialize(plan, from: source, to: destination, destinationRoot: request.destinationURL,
                                              preserveMetadata: request.options.preserveMetadata)
                        continuation.yield(.init(phase: .finalizing, completedUnits: UInt64(index + 1),
                                                 totalUnits: UInt64(plans.count), currentEntryPath: plan.entry.path))
                    }
                    await selection.backend.close(opened); handle = nil
                    try? FileManager.default.removeItem(at: stage); staging = nil
                    continuation.finish()
                } catch {
                    if let handle, let backend { await backend.close(handle) }
                    if let staging { try? FileManager.default.removeItem(at: staging) }
                    continuation.finish(throwing: ApplicationError.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeStagingDirectory(beside destination: URL) throws -> URL {
        let parent = destination.deletingLastPathComponent()
        let base = parent.appendingPathComponent(CrashSafeFilesystem.temporaryDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let stage = base.appendingPathComponent("\(UUID().uuidString)-extract", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return stage
    }

    private func resolvedDestination(for plan: ValidatedExtractionEntry, policy: ConflictResolution,
                                     remaining: inout ConflictResolution?) async throws -> URL? {
        guard FileManager.default.fileExists(atPath: plan.destinationURL.path) else { return plan.destinationURL }
        var decision = remaining ?? policy
        Self.logger.notice("conflict detected; path=\(plan.destinationURL.path, privacy: .private(mask: .hash)); effectiveConflict=\(decision.rawValue, privacy: .public)")
        if decision == .ask {
            Self.logger.notice("requesting conflict resolution; path=\(plan.destinationURL.path, privacy: .private(mask: .hash))")
            let resolved = try await conflictResolver.resolve(.init(destinationURL: plan.destinationURL, entry: plan.entry))
            decision = resolved.resolution
            Self.logger.notice("conflict decision received; decision=\(decision.rawValue, privacy: .public); scope=\(resolved.scope.rawValue, privacy: .public)")
            if resolved.scope == .remainingOperation { remaining = decision }
        }
        switch decision {
        case .replace: return plan.destinationURL
        case .skip: return nil
        case .keepBoth: return availableKeepBothURL(for: plan.destinationURL)
        case .ask: throw ApplicationError(.filesystemFailure, message: "Conflict resolver returned ask",
                                          diagnosticCode: "UNRESOLVED_CONFLICT")
        }
    }

    private func availableKeepBothURL(for url: URL) -> URL {
        let extensionPart = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let parent = url.deletingLastPathComponent()
        for index in 2...Int.max {
            var candidate = parent.appendingPathComponent("\(base) \(index)")
            if !extensionPart.isEmpty { candidate.appendPathExtension(extensionPart) }
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    private func materialize(_ plan: ValidatedExtractionEntry, from source: URL, to destination: URL,
                             destinationRoot: URL,
                             preserveMetadata: Bool) async throws {
        switch plan.entry.kind {
        case .directory:
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        case .regularFile:
            Self.logger.notice("materialization proceeding; destination=\(destination.path, privacy: .private(mask: .hash))")
            try await filesystem.materializeExtractedFile(at: destination) { partial in
                FileManager.default.createFile(atPath: partial.path, contents: nil)
                let reader = try FileHandle(forReadingFrom: source)
                let writer = try FileHandle(forWritingTo: partial)
                defer { try? reader.close(); try? writer.close() }
                while true {
                    try Task.checkCancellation()
                    guard let data = try reader.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
                    try writer.write(contentsOf: data)
                }
            }
            if preserveMetadata { try restoreMetadata(plan.entry, at: destination) }
        case .symbolicLink:
            guard plan.symlinkTarget != nil, let target = plan.entry.linkTarget else { return }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
        case .hardLink:
            guard let link = plan.hardlink else { return }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.linkItem(at: link.target.appending(to: destinationRoot), to: destination)
        default:
            throw ApplicationError(.unsafeArchiveEntry, message: "Unsupported extracted entry type: \(plan.entry.kind)",
                                   diagnosticCode: "UNSUPPORTED_ENTRY_TYPE")
        }
    }

    private func restoreMetadata(_ entry: ArchiveEntry, at url: URL) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        if let mode = entry.posixMode { attributes[.posixPermissions] = NSNumber(value: mode) }
        if let date = entry.modificationDate { attributes[.modificationDate] = date }
        if !attributes.isEmpty { try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path) }
    }
}
