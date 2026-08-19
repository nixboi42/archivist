import Foundation
import OSLog

public struct OrphanCleanupResult: Hashable, Sendable {
    public let removedFiles: Int
    public let retainedFiles: Int

    public init(removedFiles: Int, retainedFiles: Int) {
        self.removedFiles = removedFiles
        self.retainedFiles = retainedFiles
    }
}

/// The sole commit boundary for archive rewrites and extracted regular files.
/// Backends write candidates, but this type owns validation, durability and visibility.
public actor CrashSafeFilesystem {
    private static let logger = Logger(subsystem: "com.keremgurevin.Archivist", category: "filesystem-materialization")
    public static let temporaryDirectoryName = ".archiveutil-tmp"
    public static let archivePartialSuffix = ".partial"
    public static let extractionPartialSuffix = ".archiveutil-partial"

    private let fileManager: FileManager
    private var activePartialPaths: Set<String> = []

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Writes and validates a same-volume archive candidate before atomically replacing `destination`.
    /// The existing destination is never removed before the final rename(2).
    public func replaceArchive(
        at destination: URL,
        write: @Sendable (URL) async throws -> Void,
        validate: @Sendable (URL) async throws -> Void
    ) async throws {
        let parent = try parentDirectory(of: destination)
        let temporaryDirectory = parent.appendingPathComponent(Self.temporaryDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        let candidate = temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(String(Self.archivePartialSuffix.dropFirst()))

        defer { try? fileManager.removeItem(at: candidate) }
        try Task.checkCancellation()
        try await write(candidate)
        try Task.checkCancellation()
        try requireRegularFile(at: candidate)
        try verifySameVolume(candidate, destinationParent: parent)
        try await validate(candidate)
        try Task.checkCancellation()
        try POSIXDurability.syncFile(at: candidate)
        try POSIXDurability.syncDirectory(at: temporaryDirectory)
        try Task.checkCancellation()
        try POSIXDurability.atomicRename(from: candidate, to: destination)
        try POSIXDurability.syncDirectory(at: parent)
    }

    /// Creates and commits a numbered multipart archive as one recoverable transaction.
    /// Existing volumes are moved aside until every new volume is durable and visible.
    public func replaceArchiveSet(
        at destinationBase: URL,
        write: @Sendable (URL) async throws -> Void,
        validate: @Sendable (URL) async throws -> Void
    ) async throws -> [URL] {
        let parent = try parentDirectory(of: destinationBase)
        let transaction = parent.appendingPathComponent(Self.temporaryDirectoryName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let candidateBase = transaction.appendingPathComponent(destinationBase.lastPathComponent)
        let backup = transaction.appendingPathComponent("previous", isDirectory: true)
        try fileManager.createDirectory(at: transaction, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        defer { try? fileManager.removeItem(at: transaction) }

        try await write(candidateBase)
        try Task.checkCancellation()
        let candidates = try numberedVolumes(for: candidateBase)
        guard !candidates.isEmpty else {
            throw CrashSafeFilesystemError(.temporaryOutputMissing, path: candidateBase.path,
                                             message: "The writer did not produce a numbered volume set")
        }
        try await validate(candidates[0])
        for candidate in candidates {
            try requireRegularFile(at: candidate)
            try verifySameVolume(candidate, destinationParent: parent)
            try POSIXDurability.syncFile(at: candidate)
        }
        try POSIXDurability.syncDirectory(at: transaction)

        let destinations = candidates.enumerated().map { index, _ in
            URL(fileURLWithPath: destinationBase.path + String(format: ".%03d", index + 1))
        }
        let existing = try existingNumberedVolumes(for: destinationBase)
        var committed: [(source: URL, destination: URL)] = []
        var backups: [(backup: URL, destination: URL)] = []
        do {
            if !existing.isEmpty { try fileManager.createDirectory(at: backup, withIntermediateDirectories: true) }
            for old in existing {
                let saved = backup.appendingPathComponent(old.lastPathComponent)
                try fileManager.moveItem(at: old, to: saved); backups.append((saved, old))
            }
            for (candidate, destination) in zip(candidates, destinations) {
                try Task.checkCancellation()
                try fileManager.moveItem(at: candidate, to: destination)
                committed.append((candidate, destination))
            }
            try POSIXDurability.syncDirectory(at: parent)
            return destinations
        } catch {
            for item in committed.reversed() where fileManager.fileExists(atPath: item.destination.path) {
                try? fileManager.moveItem(at: item.destination, to: item.source)
            }
            for item in backups.reversed() where fileManager.fileExists(atPath: item.backup.path) {
                try? fileManager.moveItem(at: item.backup, to: item.destination)
            }
            try? POSIXDurability.syncDirectory(at: parent)
            throw error
        }
    }

    /// Materializes one extracted file through an invisible sibling partial and commits it atomically.
    public func materializeExtractedFile(
        at destination: URL,
        write: @Sendable (URL) async throws -> Void
    ) async throws {
        Self.logger.notice("CrashSafeFilesystem extraction commit entered; destinationAlreadyExists=\(self.fileManager.fileExists(atPath: destination.path)); destination=\(destination.path, privacy: .private(mask: .hash))")
        let parent = try parentDirectory(of: destination)
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let partial = URL(fileURLWithPath: destination.path + Self.extractionPartialSuffix)
        let key = partial.standardizedFileURL.path
        guard !activePartialPaths.contains(key), !fileManager.fileExists(atPath: partial.path) else {
            throw CrashSafeFilesystemError(.partialFileAlreadyExists, path: partial.path,
                                             message: "An extraction partial already exists at \(partial.path)")
        }
        activePartialPaths.insert(key)
        defer {
            activePartialPaths.remove(key)
            try? fileManager.removeItem(at: partial)
        }

        try Task.checkCancellation()
        try await write(partial)
        try Task.checkCancellation()
        try requireRegularFile(at: partial)
        try verifySameVolume(partial, destinationParent: parent)
        try POSIXDurability.syncFile(at: partial)
        try Task.checkCancellation()
        try POSIXDurability.atomicRename(from: partial, to: destination)
        try POSIXDurability.syncDirectory(at: parent)
    }

    /// Removes only known partial-file shapes older than `minimumAge` under explicitly supplied roots.
    public func cleanupOrphans(
        under roots: [URL],
        olderThan minimumAge: TimeInterval = 24 * 60 * 60,
        now: Date = Date()
    ) -> OrphanCleanupResult {
        var removed = 0
        var retained = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                let isArchivePartial = url.deletingLastPathComponent().lastPathComponent == Self.temporaryDirectoryName
                    && name.hasSuffix(Self.archivePartialSuffix)
                let isExtractionPartial = name.hasSuffix(Self.extractionPartialSuffix)
                guard isArchivePartial || isExtractionPartial else { continue }
                guard !activePartialPaths.contains(url.standardizedFileURL.path) else {
                    retained += 1
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true, values.isSymbolicLink != true,
                      let modified = values.contentModificationDate,
                      now.timeIntervalSince(modified) >= minimumAge else {
                    retained += 1
                    continue
                }
                do {
                    try fileManager.removeItem(at: url)
                    removed += 1
                } catch {
                    retained += 1
                }
            }
        }
        return OrphanCleanupResult(removedFiles: removed, retainedFiles: retained)
    }

    private func parentDirectory(of destination: URL) throws -> URL {
        let parent = destination.deletingLastPathComponent()
        guard parent.path != destination.path else {
            throw CrashSafeFilesystemError(.destinationHasNoParent, path: destination.path,
                                             message: "Destination has no parent directory")
        }
        return parent
    }

    private func requireRegularFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw CrashSafeFilesystemError(.temporaryOutputMissing, path: url.path,
                                             message: "The writer did not produce temporary output")
        }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
            throw CrashSafeFilesystemError(.temporaryOutputNotRegularFile, path: url.path,
                                             message: "Temporary output is not a regular file")
        }
    }

    private func verifySameVolume(_ candidate: URL, destinationParent: URL) throws {
        do {
            let candidateVolume = try candidate.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
            let destinationVolume = try destinationParent.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
            guard let candidateVolume, let destinationVolume,
                  (candidateVolume as AnyObject).isEqual(destinationVolume) else {
                throw CrashSafeFilesystemError(.differentVolume, path: candidate.path,
                                                 message: "Temporary output is not verifiably on the destination volume")
            }
        } catch let error as CrashSafeFilesystemError {
            throw error
        } catch {
            throw CrashSafeFilesystemError(.filesystemFailure, path: candidate.path,
                                             message: "Could not verify temporary-output volume: \(error)")
        }
    }

    private func numberedVolumes(for base: URL) throws -> [URL] {
        let files = try fileManager.contentsOfDirectory(at: base.deletingLastPathComponent(),
                                                        includingPropertiesForKeys: [.isRegularFileKey])
        let prefix = base.lastPathComponent + "."
        let indexed: [(Int, URL)] = files.compactMap { url in
            guard url.lastPathComponent.hasPrefix(prefix),
                  let value = Int(url.lastPathComponent.dropFirst(prefix.count)), value > 0 else { return nil }
            return (value, url)
        }.sorted { $0.0 < $1.0 }
        guard indexed.enumerated().allSatisfy({ $0.offset + 1 == $0.element.0 }) else {
            throw CrashSafeFilesystemError(.filesystemFailure, path: base.path,
                                             message: "Multipart output has a missing or non-contiguous volume")
        }
        return indexed.map(\.1)
    }

    private func existingNumberedVolumes(for base: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: base.deletingLastPathComponent().path) else { return [] }
        return try numberedVolumesAllowingEmpty(for: base)
    }

    private func numberedVolumesAllowingEmpty(for base: URL) throws -> [URL] {
        let prefix = base.lastPathComponent + "."
        return try fileManager.contentsOfDirectory(at: base.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { url in
                guard url.lastPathComponent.hasPrefix(prefix) else { return false }
                let suffix = url.lastPathComponent.dropFirst(prefix.count)
                return suffix.count == 3 && suffix.allSatisfy(\.isNumber)
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
