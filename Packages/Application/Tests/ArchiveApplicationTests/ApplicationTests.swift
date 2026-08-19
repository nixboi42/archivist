import ArchiveApplication
import BackendProtocol
import BackendRegistry
import Domain
import Foundation
import Testing

@Suite("Application use cases")
struct ApplicationUseCaseTests {
    @Test("browse selects backend, streams entries, and closes handle")
    func browseStreams() async throws {
        let backend = FakeBackend(entries: [.init(path: "one", kind: .regularFile), .init(path: "two", kind: .regularFile)])
        let registry = await registry(with: backend)
        let archive = try zipFixture()
        defer { try? FileManager.default.removeItem(at: archive) }

        var names: [String] = []
        for try await entry in BrowseUseCase(registry: registry).execute(.init(archiveURL: archive)) {
            names.append(entry.path)
        }
        #expect(names == ["one", "two"])
        #expect(backend.closeCount == 1)
    }

    @Test("creation writes and validates a crash-safe candidate")
    func creationIsCrashSafe() async throws {
        let backend = FakeBackend(entries: [])
        let registry = await registry(with: backend)
        try await withWorkspace { root in
            let destination = root.appendingPathComponent("archive.zip")
            try Data("original".utf8).write(to: destination)
            let request = CreationRequest(sourceURLs: [], destinationURL: destination,
                                          options: .init(format: .zip(.zip)), overwritePolicy: .replace)
            for try await _ in CreationUseCase(registry: registry, filesystem: .init()).execute(request) {}
            #expect(try String(contentsOf: destination, encoding: .utf8) == "candidate")
            #expect(backend.createdPaths.first?.contains(".archiveutil-tmp") == true)
            #expect(backend.testCount == 1)
        }
    }

    @Test("unsupported creation is rejected before destructive work")
    func unsupportedBeforeWrite() async throws {
        let backend = FakeBackend(entries: [], operations: [.list, .extract, .test])
        let registry = await registry(with: backend)
        try await withWorkspace { root in
            let destination = root.appendingPathComponent("archive.zip")
            try Data("original".utf8).write(to: destination)
            let stream = CreationUseCase(registry: registry, filesystem: .init()).execute(
                .init(sourceURLs: [], destinationURL: destination, options: .init(format: .zip(.zip)), overwritePolicy: .replace))
            await #expect(throws: ApplicationError.self) { for try await _ in stream {} }
            #expect(try String(contentsOf: destination, encoding: .utf8) == "original")
            #expect(backend.createdPaths.isEmpty)
        }
    }

    @Test("extraction rejects unsafe listing before backend extraction")
    func extractionUsesPlanner() async throws {
        let backend = FakeBackend(entries: [.init(path: "../../escape", kind: .regularFile)])
        let registry = await registry(with: backend)
        let archive = try zipFixture(); defer { try? FileManager.default.removeItem(at: archive) }
        try await withWorkspace { root in
            let stream = ExtractionUseCase(registry: registry, filesystem: .init()).execute(
                .init(archiveURL: archive, destinationURL: root, options: .init(conflictResolution: .replace)))
            do {
                for try await _ in stream {}
                Issue.record("Expected security rejection")
            } catch let error as ApplicationError {
                #expect(error.code == .unsafeArchiveEntry)
            }
            #expect(backend.extractCount == 0)
        }
    }

    @Test("backend failures preserve structured category")
    func backendFailureMapping() async throws {
        let failure = ArchiveBackendError(.backendCrashed, backendIdentifier: "fake", operation: .list,
                                          message: "helper exited", diagnosticCode: "SIGNAL_9")
        let backend = FakeBackend(entries: [], listFailure: failure)
        let registry = await registry(with: backend)
        let archive = try zipFixture(); defer { try? FileManager.default.removeItem(at: archive) }
        do {
            for try await _ in BrowseUseCase(registry: registry).execute(.init(archiveURL: archive)) {}
            Issue.record("Expected failure")
        } catch let error as ApplicationError {
            #expect(error.code == .backendCrash)
            #expect(error.diagnosticCode == "SIGNAL_9")
        }
    }

    @Test("browse cancellation reaches backend stream and closes handle")
    func browseCancellation() async throws {
        let backend = FakeBackend(entries: [
            .init(path: "one", kind: .regularFile), .init(path: "two", kind: .regularFile)
        ], listDelay: .milliseconds(100))
        let registry = await registry(with: backend)
        let archive = try zipFixture(); defer { try? FileManager.default.removeItem(at: archive) }
        let task = Task {
            for try await _ in BrowseUseCase(registry: registry).execute(.init(archiveURL: archive)) {}
        }
        try await Task.sleep(for: .milliseconds(20)); task.cancel()
        _ = try? await task.value
        for _ in 0..<50 where backend.closeCount == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(backend.closeCount == 1)
        #expect(backend.listCancellationCount == 1)
    }

    private func registry(with backend: FakeBackend) async -> ArchiveBackendRegistry {
        let registry = ArchiveBackendRegistry()
        await registry.register(backend, kind: .custom)
        return registry
    }

    private func zipFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
        try Data([0x50, 0x4b, 0x03, 0x04]).write(to: url)
        return url
    }

    private func withWorkspace(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }
}

@Suite("Archive drag export")
struct ArchiveDragExportTests {
    let entries: [ArchiveEntry] = [
        .init(path: "A.txt", kind: .regularFile),
        .init(path: "B.txt", kind: .regularFile),
        .init(path: "Folder", kind: .directory),
        .init(path: "Folder/Child.txt", kind: .regularFile),
        .init(path: "Folder/Sub", kind: .directory),
        .init(path: "Folder/Sub/Ünicode.txt", kind: .regularFile)
    ]

    @Test("single, multiple, folder, and mixed selections resolve deterministically")
    func selectionShapes() throws {
        #expect(try ArchiveDragExportSelection.resolve(selectedIDs: ["A.txt"], in: entries).roots.map(\.id) == ["A.txt"])
        #expect(try ArchiveDragExportSelection.resolve(selectedIDs: ["A.txt", "B.txt"], in: entries).roots.map(\.id) == ["A.txt", "B.txt"])
        let folder = try ArchiveDragExportSelection.resolve(selectedIDs: ["Folder"], in: entries)
        #expect(folder.entries.map(\.id) == ["Folder", "Folder/Child.txt", "Folder/Sub", "Folder/Sub/Ünicode.txt"])
        #expect(try ArchiveDragExportSelection.resolve(selectedIDs: ["A.txt", "Folder"], in: entries).roots.map(\.id) == ["A.txt", "Folder"])
    }

    @Test("selected folder makes descendant selections redundant")
    func collapsesAncestorAndChild() throws {
        let result = try ArchiveDragExportSelection.resolve(selectedIDs: ["Folder", "Folder/Child.txt", "Folder/Sub/Ünicode.txt"], in: entries)
        #expect(result.roots.map(\.id) == ["Folder"])
        #expect(result.entries.contains { $0.path == "Folder/Sub/Ünicode.txt" })
    }

    @Test("export extracts only selected roots and descendants into a private artifact")
    func selectedMaterialization() async throws {
        let backend = FakeBackend(entries: entries, materializeOnExtract: true)
        let registry = ArchiveBackendRegistry(); await registry.register(backend, kind: .custom)
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
        try Data([0x50, 0x4b, 0x03, 0x04]).write(to: archive); defer { try? FileManager.default.removeItem(at: archive) }
        let artifact = try await ArchiveDragExportUseCase(registry: registry, filesystem: .init()).execute(
            .init(archiveURL: archive, selectedEntryIDs: ["A.txt", "Folder"]))
        defer { artifact.cleanup() }
        #expect(artifact.rootURL.path.contains("com.keremgurevin.Archivist/DragExports"))
        #expect(FileManager.default.fileExists(atPath: artifact.promisedURLsByEntryID["A.txt"]!.path))
        #expect(FileManager.default.fileExists(atPath: artifact.promisedURLsByEntryID["Folder"]!.appendingPathComponent("Sub/Ünicode.txt").path))
        #expect(backend.lastExtractedEntryIDs == ["A.txt", "Folder", "Folder/Child.txt", "Folder/Sub", "Folder/Sub/Ünicode.txt"])
    }

    @Test("artifact cleanup removes the complete operation root")
    func cleanup() async throws {
        let backend = FakeBackend(entries: [.init(path: "A.txt", kind: .regularFile)], materializeOnExtract: true)
        let registry = ArchiveBackendRegistry(); await registry.register(backend, kind: .custom)
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
        try Data([0x50, 0x4b, 0x03, 0x04]).write(to: archive); defer { try? FileManager.default.removeItem(at: archive) }
        let artifact = try await ArchiveDragExportUseCase(registry: registry, filesystem: .init()).execute(
            .init(archiveURL: archive, selectedEntryIDs: ["A.txt"]))
        let root = artifact.rootURL; artifact.cleanup()
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

@Suite("Job queue")
struct JobQueueTests {
    @Test("bounded concurrency and FIFO completion")
    func boundedConcurrency() async throws {
        let queue = JobQueue(maximumConcurrentJobs: 2), probe = ConcurrencyProbe()
        for index in 0..<4 {
            let descriptor = JobDescriptor(kind: .test, sourceURLs: [URL(fileURLWithPath: "/\(index)")])
            await queue.enqueue(descriptor) { _ in
                await probe.started(index)
                try await Task.sleep(for: .milliseconds(40))
                await probe.finished(index)
            }
        }
        try await waitUntil { await queue.snapshots().allSatisfy { $0.state == .completed } }
        #expect(await probe.maximum == 2)
        #expect(await probe.startOrder.prefix(2) == [0, 1])
    }

    @Test("queued cancellation prevents execution")
    func queuedCancellation() async throws {
        let queue = JobQueue(maximumConcurrentJobs: 1), gate = Gate(), probe = ConcurrencyProbe()
        let first = JobDescriptor(kind: .test, sourceURLs: [])
        let second = JobDescriptor(kind: .test, sourceURLs: [])
        await queue.enqueue(first) { _ in await gate.wait() }
        await queue.enqueue(second) { _ in await probe.started(2) }
        await queue.cancel(second.id)
        await gate.open()
        try await waitUntil { await queue.snapshot(first.id)?.state == .completed }
        #expect(await queue.snapshot(second.id)?.state == .cancelled)
        #expect(await probe.startOrder.isEmpty)
    }

    @Test("running cancellation remains cancellation")
    func runningCancellation() async throws {
        let queue = JobQueue(maximumConcurrentJobs: 1)
        let descriptor = JobDescriptor(kind: .extract, sourceURLs: [])
        await queue.enqueue(descriptor) { _ in try await Task.sleep(for: .seconds(30)) }
        try await waitUntil { await queue.snapshot(descriptor.id)?.state == .running }
        await queue.cancel(descriptor.id)
        try await waitUntil { await queue.snapshot(descriptor.id)?.state == .cancelled }
    }

    @Test("failed job retries exactly once and completes")
    func retry() async throws {
        let queue = JobQueue(maximumConcurrentJobs: 1), attempts = AttemptCounter()
        let descriptor = JobDescriptor(kind: .create, sourceURLs: [])
        await queue.enqueue(descriptor) { _ in
            if await attempts.next() == 1 { throw ArchiveBackendError(.backendFailure, message: "first") }
        }
        try await waitUntil {
            guard let state = await queue.snapshot(descriptor.id)?.state else { return false }
            if case .failed = state { return true }; return false
        }
        try await queue.retry(descriptor.id)
        try await waitUntil { await queue.snapshot(descriptor.id)?.state == .completed }
        #expect(await queue.snapshot(descriptor.id)?.attempt == 2)
        #expect(await attempts.value == 2)
    }

    private func waitUntil(_ predicate: @escaping @Sendable () async -> Bool) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for queue state")
    }
}

private final class FakeBackend: ArchiveBackend, @unchecked Sendable {
    let identifier = BackendIdentifier(rawValue: "fake")
    private let lock = NSLock()
    private let entries: [ArchiveEntry]
    private let operations: Set<ArchiveOperation>
    private let listFailure: Error?
    private let listDelay: Duration?
    private let materializeOnExtract: Bool
    private var _closeCount = 0, _testCount = 0, _extractCount = 0, _listCancellationCount = 0
    private var _createdPaths: [String] = []
    private var _lastExtractedEntryIDs: [String] = []

    init(entries: [ArchiveEntry], operations: Set<ArchiveOperation> = [.read, .list, .extract, .create, .test],
         listFailure: Error? = nil, listDelay: Duration? = nil, materializeOnExtract: Bool = false) {
        self.entries = entries; self.operations = operations; self.listFailure = listFailure; self.listDelay = listDelay
        self.materializeOnExtract = materializeOnExtract
    }
    var closeCount: Int { lock.withLock { _closeCount } }
    var testCount: Int { lock.withLock { _testCount } }
    var extractCount: Int { lock.withLock { _extractCount } }
    var listCancellationCount: Int { lock.withLock { _listCancellationCount } }
    var createdPaths: [String] { lock.withLock { _createdPaths } }
    var lastExtractedEntryIDs: [String] { lock.withLock { _lastExtractedEntryIDs } }
    func capabilities(for format: ArchiveFormat) -> ArchiveCapabilities {
        .init(operations: operations, creationOptions: operations.contains(.create) ? .init() : nil)
    }
    func open(_ url: URL, format: ArchiveFormat, credential: ArchiveCredential?) async throws -> ArchiveHandle {
        .init(backend: identifier, format: format)
    }
    func list(_ handle: ArchiveHandle) -> AsyncThrowingStream<ArchiveEntry, Error> {
        AsyncThrowingStream { continuation in
            if let listFailure { continuation.finish(throwing: listFailure); return }
            let task = Task {
                do {
                    for entry in entries {
                        if let listDelay { try await Task.sleep(for: listDelay) }
                        try Task.checkCancellation(); continuation.yield(entry)
                    }
                    continuation.finish()
                } catch {
                    lock.withLock { _listCancellationCount += 1 }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    func extract(_ handle: ArchiveHandle, entries: [ArchiveEntry]?, to destination: URL,
                 options: ExtractionOptions) -> AsyncThrowingStream<ProgressEvent, Error> {
        let selected = entries ?? self.entries
        lock.withLock { _extractCount += 1; _lastExtractedEntryIDs = selected.map(\.id) }
        return AsyncThrowingStream { continuation in
            do {
                if materializeOnExtract {
                    for entry in selected {
                        let url = destination.appendingPathComponent(entry.path)
                        if entry.kind == .directory { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
                        else {
                            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try Data(entry.path.utf8).write(to: url)
                        }
                    }
                }
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }
    func create(from sources: [URL], to destination: URL,
                options: CreationOptions) -> AsyncThrowingStream<ProgressEvent, Error> {
        lock.withLock { _createdPaths.append(destination.path) }
        return AsyncThrowingStream { continuation in
            do { try Data("candidate".utf8).write(to: destination); continuation.finish() }
            catch { continuation.finish(throwing: error) }
        }
    }
    func test(_ handle: ArchiveHandle) -> AsyncThrowingStream<ProgressEvent, Error> {
        lock.withLock { _testCount += 1 }; return AsyncThrowingStream { $0.finish() }
    }
    func close(_ handle: ArchiveHandle) async { lock.withLock { _closeCount += 1 } }
}

private actor ConcurrencyProbe {
    private(set) var current = 0, maximum = 0
    private(set) var startOrder: [Int] = []
    func started(_ id: Int) { current += 1; maximum = max(maximum, current); startOrder.append(id) }
    func finished(_ id: Int) { current -= 1 }
}

private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async { if opened { return }; await withCheckedContinuation { continuation = $0 } }
    func open() { opened = true; continuation?.resume(); continuation = nil }
}

private actor AttemptCounter {
    private(set) var value = 0
    func next() -> Int { value += 1; return value }
}
