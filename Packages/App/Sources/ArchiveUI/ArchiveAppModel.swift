import AppKit
import ArchiveApplication
import BackendProtocol
import BackendRegistry
import Combine
import CrashSafeFilesystem
import Domain
import Foundation
import OSLog

@MainActor
public final class ArchiveAppModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.keremgurevin.Archivist", category: "conflict-policy")
    @Published public private(set) var archiveURL: URL?
    @Published public var browser = ArchiveBrowserModel()
    @Published public var selection: Set<ArchiveEntry.ID> = []
    @Published public private(set) var isScanning = false
    @Published public private(set) var scanCount = 0
    @Published public var errorPresentation: ErrorPresentation?
    @Published public var showingCreation = false
    @Published public var pendingCreationSources: [URL] = []
    @Published public var pendingCreationFormat: ArchiveFormat?
    @Published public var showingInspector = true
    @Published public var showingJobs = false
    @Published public private(set) var jobs: [JobSnapshot] = []
    @Published public var conflictPrompt: ConflictResolutionBroker.Prompt?
    @Published public var passwordPromptVisible = false
    @Published public var password = ""
    @Published public var verificationResult: TestArchiveResult?
    @Published public var previewWarning: ArchiveWarning?

    public let registry: ArchiveBackendRegistry
    public let filesystem: CrashSafeFilesystem
    public let queue: JobQueue
    public let conflictBroker: ConflictResolutionBroker
    private var browseTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var previewArtifact: PreviewArtifact?
    private var archiveCredential: ArchiveCredential?
    private var dragCredentialContinuation: CheckedContinuation<ArchiveCredential?, Never>?
    private var presentedFailedJobs: Set<UUID> = []
    private struct ExtractionAttempt: Sendable {
        let request: ExtractionRequest
        let logicalOperationID: UUID
        let attemptNumber: Int
        let finderPresentation: Bool
    }
    private var extractionRequests: [UUID: ExtractionAttempt] = [:]
    private var pendingPasswordExtraction: ExtractionAttempt?
    private let quickLook = QuickLookPresenter()
    private let defaults: UserDefaults
    private var observationTasks: [Task<Void, Never>] = []

    public init(registry: ArchiveBackendRegistry, maximumConcurrentJobs: Int = 2,
                defaults: UserDefaults = .standard) {
        self.registry = registry; filesystem = .init(); queue = .init(maximumConcurrentJobs: maximumConcurrentJobs)
        self.defaults = defaults
        conflictBroker = .init()
        observationTasks.append(Task { [weak self, conflictBroker] in
            for await prompt in conflictBroker.prompts { self?.conflictPrompt = prompt }
        })
        observationTasks.append(Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.jobs = await self.queue.snapshots()
                if let failed = self.jobs.first(where: {
                    if case .failed = $0.state { return !self.presentedFailedJobs.contains($0.id) }
                    return false
                }), case .failed(let error) = failed.state {
                    self.presentedFailedJobs.insert(failed.id)
                    if error.code == .wrongPassword {
                        self.pendingPasswordExtraction = self.extractionRequests[failed.id]
                        self.passwordPromptVisible = true
                    }
                    else { self.errorPresentation = .init(error) }
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        })
    }

    deinit { browseTask?.cancel(); previewTask?.cancel(); previewArtifact?.cleanup(); observationTasks.forEach { $0.cancel() } }

    public var selectedEntries: [ArchiveEntry] { selection.compactMap { browser.entry(id: $0) } }

    public func presentOpenPanel() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in if response == .OK, let url = panel.url { Task { @MainActor in self?.open(url) } } }
    }

    public func open(_ url: URL, credential: ArchiveCredential? = nil) {
        browseTask?.cancel(); archiveURL = url; archiveCredential = credential; browser.reset(); selection = []; scanCount = 0; isScanning = true
        verificationResult = nil
        browseTask = Task { [weak self] in
            guard let self else { return }
            var batch: [ArchiveEntry] = []; batch.reserveCapacity(128)
            do {
                for try await entry in BrowseUseCase(registry: registry).execute(.init(archiveURL: url, credential: credential)) {
                    batch.append(entry)
                    if batch.count >= 128 { browser.append(contentsOf: batch); scanCount += batch.count; batch.removeAll(keepingCapacity: true) }
                }
                if !batch.isEmpty { browser.append(contentsOf: batch); scanCount += batch.count }
                isScanning = false
            } catch let error as ApplicationError {
                isScanning = false
                if error.code == .wrongPassword { passwordPromptVisible = true }
                else if error.code != .cancelled { errorPresentation = .init(error) }
            } catch { isScanning = false; errorPresentation = .init(ApplicationError.map(error)) }
        }
    }

    public func submitPassword() {
        guard !password.isEmpty else { return }
        let credential = ArchiveCredential(password: password); password = ""; passwordPromptVisible = false
        if let continuation = dragCredentialContinuation {
            dragCredentialContinuation = nil
            continuation.resume(returning: credential)
        } else if let pending = pendingPasswordExtraction {
            pendingPasswordExtraction = nil
            let request = pending.request.withCredential(credential)
            Self.logger.notice("credential retry prepared; operationID=\(pending.logicalOperationID.uuidString, privacy: .public); attempt=\(pending.attemptNumber + 1); conflict=\(request.options.conflictResolution.rawValue, privacy: .public); resolver=present; selectedEntries=\(request.selectedEntryIDs?.count ?? -1); preserveMetadata=\(request.options.preserveMetadata); credentialPresent=true; finderPresentation=\(pending.finderPresentation)")
            enqueueExtraction(request, logicalOperationID: pending.logicalOperationID,
                              attemptNumber: pending.attemptNumber + 1,
                              finderPresentation: pending.finderPresentation)
        } else if let archiveURL { open(archiveURL, credential: credential) }
    }

    public func cancelPassword() {
        password = ""; passwordPromptVisible = false; pendingPasswordExtraction = nil
        dragCredentialContinuation?.resume(returning: nil); dragCredentialContinuation = nil
    }

    func requestDragCredential() async -> ArchiveCredential? {
        return await withCheckedContinuation { continuation in
            dragCredentialContinuation?.resume(returning: nil)
            dragCredentialContinuation = continuation
            passwordPromptVisible = true
        }
    }

    func makeDragExportSession(entryIDs: Set<ArchiveEntry.ID>) -> ArchiveDragExportSession? {
        guard let archiveURL, !entryIDs.isEmpty else { return nil }
        let security = SecurityPolicy(preventPathTraversal: defaults.object(forKey: "preventPathTraversal") as? Bool ?? true,
                                      restrictUnsafeSymlinks: defaults.object(forKey: "restrictSymlinks") as? Bool ?? true,
                                      restrictUnsafeHardlinks: defaults.object(forKey: "restrictHardlinks") as? Bool ?? true,
                                      rejectUnicodeCollisions: defaults.object(forKey: "rejectUnicodeCollisions") as? Bool ?? true)
        return ArchiveDragExportSession(
            useCase: .init(registry: registry, filesystem: filesystem), archiveURL: archiveURL,
            selectedEntryIDs: entryIDs, initialCredential: archiveCredential, securityPolicy: security,
            queue: queue,
            requestCredential: { [weak self] in await self?.requestDragCredential() },
            presentError: { [weak self] error in self?.errorPresentation = .init(error) })
    }

    public func closeArchive() { browseTask?.cancel(); archiveURL = nil; archiveCredential = nil; browser.reset(); selection = []; isScanning = false }

    public func activate(_ entry: ArchiveEntry) {
        if entry.kind == .directory { browser.enter(entry); return }
        guard entry.kind == .regularFile, let archiveURL else { return }
        previewTask?.cancel(); previewArtifact?.cleanup(); previewArtifact = nil; previewWarning = nil
        let useCase = PreviewUseCase(registry: registry, filesystem: filesystem), credential = archiveCredential
        previewTask = Task { [weak self] in
            do {
                let artifact = try await useCase.execute(.init(archiveURL: archiveURL, entry: entry, credential: credential))
                guard let self else { artifact.cleanup(); return }
                self.previewArtifact = artifact; self.previewWarning = artifact.warning; self.quickLook.present(artifact.fileURL)
            } catch let error as ApplicationError where error.code == .cancelled { }
            catch { self?.errorPresentation = .init(ApplicationError.map(error)) }
        }
    }

    public func presentExtractionPanel(selectedOnly: Bool) {
        guard archiveURL != nil else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            if response == .OK, let destination = panel.url { Task { @MainActor in self?.startExtraction(to: destination, selectedOnly: selectedOnly) } }
        }
    }

    public func startExtraction(to destination: URL, selectedOnly: Bool) {
        guard let archiveURL else { return }
        let ids = selectedOnly ? selection : nil
        enqueueExtraction(archive: archiveURL, destination: destination, ids: ids, credential: archiveCredential)
    }

    public func startExtractionForFinder(archive: URL, destination: URL) {
        enqueueExtraction(archive: archive, destination: destination, ids: nil, credential: nil,
                          finderPresentation: true)
    }

    private func enqueueExtraction(archive: URL, destination: URL, ids: Set<ArchiveEntry.ID>?,
                                   credential: ArchiveCredential?, finderPresentation: Bool = false) {
        let conflict: ConflictResolution = switch defaults.string(forKey: "defaultConflict") {
        case "replace": .replace; case "skip": .skip; case "keepBoth": .keepBoth; default: .ask
        }
        Self.logger.notice("extraction request constructed; effectiveConflict=\(conflict.rawValue, privacy: .public); destination=\(destination.path, privacy: .private(mask: .hash))")
        let security = SecurityPolicy(preventPathTraversal: defaults.object(forKey: "preventPathTraversal") as? Bool ?? true,
                                      restrictUnsafeSymlinks: defaults.object(forKey: "restrictSymlinks") as? Bool ?? true,
                                      restrictUnsafeHardlinks: defaults.object(forKey: "restrictHardlinks") as? Bool ?? true,
                                      rejectUnicodeCollisions: defaults.object(forKey: "rejectUnicodeCollisions") as? Bool ?? true)
        let request = ExtractionRequest(archiveURL: archive, selectedEntryIDs: ids, destinationURL: destination,
                                        options: .init(conflictResolution: conflict, credential: credential,
                                                       securityPolicy: security))
        enqueueExtraction(request, finderPresentation: finderPresentation)
    }

    private func enqueueExtraction(_ request: ExtractionRequest, logicalOperationID: UUID = UUID(),
                                   attemptNumber: Int = 1, finderPresentation: Bool = false) {
        let useCase = ExtractionUseCase(registry: registry, filesystem: filesystem, conflictResolver: conflictBroker)
        let descriptor = JobDescriptor(kind: .extract, sourceURLs: [request.archiveURL], destinationURL: request.destinationURL)
        Self.logger.notice("extraction enqueued; jobID=\(descriptor.id.uuidString, privacy: .public); operationID=\(logicalOperationID.uuidString, privacy: .public); attempt=\(attemptNumber); archive=\(request.archiveURL.path, privacy: .private(mask: .hash)); destination=\(request.destinationURL.path, privacy: .private(mask: .hash)); selectedEntries=\(request.selectedEntryIDs?.count ?? -1); conflict=\(request.options.conflictResolution.rawValue, privacy: .public); resolver=present; preserveMetadata=\(request.options.preserveMetadata); credentialPresent=\(request.options.credential != nil); finderPresentation=\(finderPresentation)")
        extractionRequests[descriptor.id] = .init(request: request, logicalOperationID: logicalOperationID,
                                                  attemptNumber: attemptNumber,
                                                  finderPresentation: finderPresentation)
        Task { await queue.enqueue(descriptor) { report in for try await event in useCase.execute(request) { report(event) } } }
    }

    public func startCreation(_ request: CreationRequest) {
        let useCase = CreationUseCase(registry: registry, filesystem: filesystem, conflictResolver: conflictBroker)
        let descriptor = JobDescriptor(kind: .create, sourceURLs: request.sourceURLs,
                                       destinationURL: request.destinationURL, format: request.options.format)
        Task { await queue.enqueue(descriptor) { report in for try await event in useCase.execute(request) { report(event) } } }
        showingCreation = false; pendingCreationSources = []; pendingCreationFormat = nil
    }

    public func startFinderCreation(sources: [URL], format: ArchiveFormat, destination: URL) {
        startCreation(.init(sourceURLs: sources, destinationURL: destination,
                            options: .init(format: format), overwritePolicy: .ask))
    }

    public func beginCreation(sources: [URL] = [], format: ArchiveFormat? = nil) {
        pendingCreationSources = sources; pendingCreationFormat = format; showingCreation = true
    }

    public func testArchive() {
        guard let archiveURL else { return }
        let useCase = TestArchiveUseCase(registry: registry), descriptor = JobDescriptor(kind: .test, sourceURLs: [archiveURL]), queue = self.queue, credential = archiveCredential
        Task { [queue, descriptor, useCase, archiveURL, credential, weak self] in await queue.enqueue(descriptor) { [weak self] report in
            let result = try await useCase.execute(archiveURL, credential: credential, onProgress: report)
            await MainActor.run { self?.verificationResult = result }
        } }
        showingJobs = true
    }

    public func cancelJob(_ id: UUID) { Task { await queue.cancel(id) } }
    public func retryJob(_ id: UUID) { Task { try? await queue.retry(id) } }
    public func answerConflict(_ resolution: ConflictResolution, remaining: Bool) {
        conflictPrompt = nil
        Task { await conflictBroker.answer(.init(resolution, scope: remaining ? .remainingOperation : .singleEntry)) }
    }
}
