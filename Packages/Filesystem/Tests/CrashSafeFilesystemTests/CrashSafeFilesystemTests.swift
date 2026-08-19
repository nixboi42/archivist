import CrashSafeFilesystem
import Foundation
import Testing

@Suite("Crash-safe filesystem")
struct CrashSafeFilesystemTests {
    @Test("validated archive atomically replaces the original")
    func successfulReplacement() async throws {
        try await withWorkspace { root in
            let destination = root.appendingPathComponent("archive.zip")
            try Data("old".utf8).write(to: destination)
            let filesystem = CrashSafeFilesystem()

            try await filesystem.replaceArchive(at: destination) { candidate in
                try Data("new".utf8).write(to: candidate)
            } validate: { candidate in
                let contents = try String(contentsOf: candidate, encoding: .utf8)
                #expect(contents == "new")
            }

            #expect(try String(contentsOf: destination, encoding: .utf8) == "new")
            #expect(try partials(in: root).isEmpty)
        }
    }

    @Test("writer failure leaves original intact and removes partial")
    func writerFailure() async throws {
        try await withWorkspace { root in
            let destination = root.appendingPathComponent("archive.zip")
            try Data("old".utf8).write(to: destination)
            let filesystem = CrashSafeFilesystem()

            await #expect(throws: SimulatedFailure.self) {
                try await filesystem.replaceArchive(at: destination) { candidate in
                    try Data("incomplete".utf8).write(to: candidate)
                    throw SimulatedFailure()
                } validate: { _ in }
            }
            #expect(try String(contentsOf: destination, encoding: .utf8) == "old")
            #expect(try partials(in: root).isEmpty)
        }
    }

    @Test("validation failure leaves original intact")
    func validationFailure() async throws {
        try await withWorkspace { root in
            let destination = root.appendingPathComponent("archive.zip")
            try Data("old".utf8).write(to: destination)
            let filesystem = CrashSafeFilesystem()

            await #expect(throws: SimulatedFailure.self) {
                try await filesystem.replaceArchive(at: destination) { candidate in
                    try Data("invalid".utf8).write(to: candidate)
                } validate: { _ in
                    throw SimulatedFailure()
                }
            }
            #expect(try String(contentsOf: destination, encoding: .utf8) == "old")
            #expect(try partials(in: root).isEmpty)
        }
    }

    @Test("cancellation leaves original intact")
    func cancellation() async throws {
        try await withWorkspace { root in
            let destination = root.appendingPathComponent("archive.zip")
            try Data("old".utf8).write(to: destination)
            let filesystem = CrashSafeFilesystem()

            let task = Task {
                try await filesystem.replaceArchive(at: destination) { candidate in
                    try Data("incomplete".utf8).write(to: candidate)
                    throw CancellationError()
                } validate: { _ in }
            }
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(try String(contentsOf: destination, encoding: .utf8) == "old")
            #expect(try partials(in: root).isEmpty)
        }
    }

    @Test("extracted file is invisible until complete")
    func extractedFileCommit() async throws {
        try await withWorkspace { root in
            let destination = root.appendingPathComponent("entry.txt")
            let filesystem = CrashSafeFilesystem()

            try await filesystem.materializeExtractedFile(at: destination) { partial in
                #expect(!FileManager.default.fileExists(atPath: destination.path))
                #expect(partial.path == destination.path + ".archiveutil-partial")
                try Data("complete".utf8).write(to: partial)
            }
            #expect(try String(contentsOf: destination, encoding: .utf8) == "complete")
            #expect(!FileManager.default.fileExists(atPath: destination.path + ".archiveutil-partial"))
        }
    }

    @Test("failed extraction preserves an existing destination")
    func failedExtraction() async throws {
        try await withWorkspace { root in
            let destination = root.appendingPathComponent("entry.txt")
            try Data("old".utf8).write(to: destination)
            let filesystem = CrashSafeFilesystem()

            await #expect(throws: SimulatedFailure.self) {
                try await filesystem.materializeExtractedFile(at: destination) { partial in
                    try Data("half".utf8).write(to: partial)
                    throw SimulatedFailure()
                }
            }
            #expect(try String(contentsOf: destination, encoding: .utf8) == "old")
            #expect(!FileManager.default.fileExists(atPath: destination.path + ".archiveutil-partial"))
        }
    }

    @Test("orphan sweep removes only stale recognized regular files")
    func orphanCleanup() async throws {
        try await withWorkspace { root in
            let temp = root.appendingPathComponent(".archiveutil-tmp", isDirectory: true)
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let oldArchive = temp.appendingPathComponent("old.partial")
            let freshArchive = temp.appendingPathComponent("fresh.partial")
            let oldExtraction = root.appendingPathComponent("entry.archiveutil-partial")
            let unrelated = root.appendingPathComponent("keep.partial")
            for url in [oldArchive, freshArchive, oldExtraction, unrelated] {
                try Data().write(to: url)
            }
            let oldDate = Date(timeIntervalSinceNow: -(25 * 60 * 60))
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldArchive.path)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldExtraction.path)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: unrelated.path)

            let result = await CrashSafeFilesystem().cleanupOrphans(under: [root])
            #expect(result == OrphanCleanupResult(removedFiles: 2, retainedFiles: 1))
            #expect(!FileManager.default.fileExists(atPath: oldArchive.path))
            #expect(FileManager.default.fileExists(atPath: freshArchive.path))
            #expect(FileManager.default.fileExists(atPath: unrelated.path))
        }
    }

    @Test("multipart commit validates the set and replaces it together")
    func multipartCommit() async throws {
        try await withWorkspace { root in
            let base = root.appendingPathComponent("Archive.7z")
            try Data("old-one".utf8).write(to: URL(fileURLWithPath: base.path + ".001"))
            try Data("old-two".utf8).write(to: URL(fileURLWithPath: base.path + ".002"))
            let filesystem = CrashSafeFilesystem()
            let committed = try await filesystem.replaceArchiveSet(at: base) { candidate in
                try Data("new-one".utf8).write(to: URL(fileURLWithPath: candidate.path + ".001"))
                try Data("new-two".utf8).write(to: URL(fileURLWithPath: candidate.path + ".002"))
            } validate: { first in
                #expect(first.lastPathComponent.hasSuffix(".001"))
                let contents = try String(contentsOf: first, encoding: .utf8)
                #expect(contents == "new-one")
            }
            #expect(committed.map(\.lastPathComponent) == ["Archive.7z.001", "Archive.7z.002"])
            #expect(try String(contentsOf: committed[0], encoding: .utf8) == "new-one")
            #expect(try String(contentsOf: committed[1], encoding: .utf8) == "new-two")
        }
    }

    @Test("multipart validation failure preserves the previous set")
    func multipartRollbackBeforeCommit() async throws {
        try await withWorkspace { root in
            let base = root.appendingPathComponent("Archive.7z")
            let first = URL(fileURLWithPath: base.path + ".001")
            try Data("old".utf8).write(to: first)
            await #expect(throws: SimulatedFailure.self) {
                try await CrashSafeFilesystem().replaceArchiveSet(at: base) { candidate in
                    try Data("invalid".utf8).write(to: URL(fileURLWithPath: candidate.path + ".001"))
                } validate: { _ in throw SimulatedFailure() }
            }
            #expect(try String(contentsOf: first, encoding: .utf8) == "old")
        }
    }

    private struct SimulatedFailure: Error {}

    private func withWorkspace(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    private func partials(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter {
            $0.lastPathComponent.hasSuffix(".partial") || $0.lastPathComponent.hasSuffix(".archiveutil-partial")
        }
    }
}
