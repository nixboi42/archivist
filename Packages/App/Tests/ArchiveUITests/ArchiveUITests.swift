import ArchiveUI
import ArchiveApplication
import BackendProtocol
import BackendRegistry
import Domain
import FinderIntegration
import Foundation
import Testing

@MainActor
@Test func launchModelStartsInEmptyState() {
    let model = ArchiveAppModel(registry: .init())
    #expect(model.archiveURL == nil); #expect(model.browser.entries.isEmpty); #expect(!model.isScanning)
}

@MainActor
@Test func finderCoordinatorRoutesDirectCreationAsBackgroundJob() async throws {
    let model = ArchiveAppModel(registry: .init())
    let sources = [URL(fileURLWithPath: "/tmp/one"), URL(fileURLWithPath: "/tmp/two")]
    let presenter = PresentationSpy()
    try FinderRequestCoordinator(model: model, presentation: presenter).route(
        ArchiveFinderRequest(action: .createZIP, urls: sources)
    )
    try await waitUntil { await model.queue.snapshots().count == 1 }
    let job = try #require(await model.queue.snapshots().first)
    #expect(job.descriptor.kind == .create)
    #expect(job.descriptor.sourceURLs == sources)
    #expect(job.descriptor.destinationURL?.path == "/tmp/Archive.zip")
    #expect(presenter.mainWindowCount == 0)
}

@Test func finderPresentationPolicyIsExplicitForEveryAction() {
    let policy = FinderPresentationPolicy()
    #expect(policy.presentation(for: .openArchive) == .mainWindow)
    #expect(policy.presentation(for: .createArchive) == .mainWindow)
    #expect(policy.presentation(for: .extractTo) == .destinationChooser)
    for action in [FinderArchiveAction.extractHere, .extractToNamed, .createSevenZip, .createZIP] {
        #expect(policy.presentation(for: action) == .background)
    }
}

@MainActor
@Test func extractToPresentsOnlyDestinationChooserWithoutOpeningArchiveBrowser() throws {
    let model = ArchiveAppModel(registry: .init()), presenter = PresentationSpy()
    let archive = URL(fileURLWithPath: "/tmp/example.zip")
    try FinderRequestCoordinator(model: model, presentation: presenter).route(.init(action: .extractTo, urls: [archive]))
    #expect(model.archiveURL == nil)
    #expect(presenter.mainWindowCount == 0)
    #expect(presenter.destinationArchive == archive)
}

@MainActor
@Test func openArchiveRequestsMainBrowserWhileBackgroundExtractionDoesNot() throws {
    let openModel = ArchiveAppModel(registry: .init()), openPresenter = PresentationSpy()
    try FinderRequestCoordinator(model: openModel, presentation: openPresenter).route(
        .init(action: .openArchive, urls: [URL(fileURLWithPath: "/tmp/archive.zip")]))
    #expect(openPresenter.mainWindowCount == 1)

    let extractionModel = ArchiveAppModel(registry: .init()), extractionPresenter = PresentationSpy()
    try FinderRequestCoordinator(model: extractionModel, presentation: extractionPresenter).route(
        .init(action: .extractHere, urls: [URL(fileURLWithPath: "/tmp/archive.zip")]))
    #expect(extractionPresenter.mainWindowCount == 0)
}

@Test func finderCreationDestinationUsesStableMultiSelectionAndSingleSourceNames() throws {
    #expect(try FinderCreationDestinationPolicy.destination(for: [URL(fileURLWithPath: "/tmp/report.txt")], format: .zip(.zip)).path == "/tmp/report.zip")
    #expect(try FinderCreationDestinationPolicy.destination(for: [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")], format: .sevenZip).path == "/tmp/Archive.7z")
}

@MainActor @Test func jobsWindowHasStablePresentationIdentity() {
    #expect(ApplicationPresentationCoordinator.jobsWindowIdentifier.rawValue == "com.archivist.jobs")
}

@MainActor @Test func requiredInteractionsUseAuxiliaryOnlyPresentation() {
    for kind in RequiredInteractionKind.allCases {
        let plan = AuxiliaryPresentationPlan(kind: kind)
        #expect(!plan.requestsMainWindow)
        #expect(plan.activatesApplication)
        #expect(plan.showBeforeActivation)
    }
    #expect(ApplicationPresentationCoordinator.interactionWindowIdentifier.rawValue == "com.archivist.required-interaction")
}

@MainActor
@Test func finderCoordinatorRoutesNamedExtractionIntoExistingJobQueue() async throws {
    let model = ArchiveAppModel(registry: .init())
    let archive = URL(fileURLWithPath: "/tmp/example.tar.gz")
    try FinderRequestCoordinator(model: model).route(
        ArchiveFinderRequest(action: .extractToNamed, urls: [archive])
    )
    try await waitUntil { await model.queue.snapshots().count == 1 }
    let job = try #require(await model.queue.snapshots().first)
    #expect(job.descriptor.kind == .extract)
    #expect(job.descriptor.sourceURLs == [archive])
    #expect(job.descriptor.destinationURL?.path == "/tmp/example")
}

@MainActor
@Test func openingArchiveStreamsEntriesIntoBrowser() async throws {
    let registry = ArchiveBackendRegistry(), backend = UIFakeBackend()
    await registry.register(backend, kind: .custom)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
    defer { try? FileManager.default.removeItem(at: url) }; try Data([0x50,0x4b,0x03,0x04]).write(to:url)
    let model = ArchiveAppModel(registry: registry); model.open(url)
    try await waitUntil { !model.isScanning }
    #expect(model.browser.entries.map(\.path) == ["folder", "folder/file.txt"])
}

@Test func browserNavigationAndSearchUseEnumeratedEntries() {
    var browser = ArchiveBrowserModel(); browser.append(contentsOf: [
        .init(path:"folder",kind:.directory), .init(path:"folder/file.txt",kind:.regularFile), .init(path:"root.txt",kind:.regularFile)
    ])
    #expect(browser.visibleEntries.map(\.path) == ["folder","root.txt"])
    browser.enter(.init(path:"folder",kind:.directory)); #expect(browser.visibleEntries.map(\.path) == ["folder/file.txt"])
    browser.searchText="root"; #expect(browser.visibleEntries.map(\.path) == ["root.txt"])
}

@Test func creationOptionsExcludeUnsupportedFormats() async {
    let registry=ArchiveBackendRegistry(),backend=UIFakeBackend();await registry.register(backend,kind:.custom)
    let options=await AvailableCreationFormatsUseCase(registry:registry).execute()
    #expect(options.contains{$0.format == ArchiveFormat.zip(.zip)})
    #expect(!options.contains{$0.format == ArchiveFormat.rar})
    #expect(!options.contains{$0.format == ArchiveFormat.cab})
    #expect(!options.contains{$0.format == ArchiveFormat.arj})
}

@Test func passwordCredentialDescriptionIsAlwaysRedacted() {
    let value=ArchiveCredential(password:"NEVER_SHOW_THIS")
    #expect(value.description == "<redacted>");#expect(!value.debugDescription.contains("NEVER_SHOW_THIS"))
}

@Test func conflictBrokerCarriesReplaceAllDecision() async throws {
    let broker=ConflictResolutionBroker(),context=ConflictContext(destinationURL:URL(fileURLWithPath:"/tmp/file"),entry:nil)
    let task=Task{try await broker.resolve(context)}
    var iterator=broker.prompts.makeAsyncIterator();let prompt=await iterator.next();#expect(prompt?.context.destinationURL.path == "/tmp/file")
    await broker.answer(.init(.replace,scope:.remainingOperation));let decision=try await task.value
    #expect(decision.resolution == .replace);#expect(decision.scope == .remainingOperation)
}

@MainActor
@Test func finderExtractionAsksBeforeMaterializationAndScopesApplyToAllPerJob() async throws {
    let suite = "ArchivistTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("ask", forKey: "defaultConflict")

    let registry = ArchiveBackendRegistry()
    let backend = FinderConflictBackend(paths: ["one.md", "two.md"])
    await registry.register(backend, kind: .custom)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let archive = root.appendingPathComponent("Archive.zip")
    try Data([0x50, 0x4b, 0x03, 0x04]).write(to: archive)

    func resetExisting() throws {
        try Data("existing-one".utf8).write(to: root.appendingPathComponent("one.md"))
        try Data("existing-two".utf8).write(to: root.appendingPathComponent("two.md"))
    }
    func start(_ model: ArchiveAppModel) throws {
        try FinderRequestCoordinator(model: model).route(.init(action: .extractHere, urls: [archive]))
    }
    func waitForFinishedJob(_ model: ArchiveAppModel) async throws {
        try await waitUntil {
            await model.queue.snapshots().contains {
                if case .completed = $0.state { return true }
                return false
            }
        }
    }

    // Replace All applies only within this extraction job.
    try resetExisting()
    let first = ArchiveAppModel(registry: registry, defaults: defaults)
    try start(first)
    try await waitUntil { first.conflictPrompt != nil }
    #expect(try String(contentsOf: root.appendingPathComponent("one.md"), encoding: .utf8) == "existing-one")
    #expect(backend.lastConflictResolution == .replace) // backend writes only to isolated staging
    first.answerConflict(.replace, remaining: true)
    try await waitForFinishedJob(first)
    #expect(try String(contentsOf: root.appendingPathComponent("one.md"), encoding: .utf8) == "incoming-one.md")
    #expect(try String(contentsOf: root.appendingPathComponent("two.md"), encoding: .utf8) == "incoming-two.md")

    // A new job asks again; the previous Replace All decision is not sticky.
    try resetExisting()
    let second = ArchiveAppModel(registry: registry, defaults: defaults)
    try start(second)
    try await waitUntil { second.conflictPrompt != nil }
    #expect(try String(contentsOf: root.appendingPathComponent("one.md"), encoding: .utf8) == "existing-one")
    second.answerConflict(.skip, remaining: true)
    try await waitForFinishedJob(second)
    #expect(try String(contentsOf: root.appendingPathComponent("one.md"), encoding: .utf8) == "existing-one")
    #expect(try String(contentsOf: root.appendingPathComponent("two.md"), encoding: .utf8) == "existing-two")

    // Keep Both preserves the original and deterministically materializes a unique sibling.
    let singleRegistry = ArchiveBackendRegistry()
    await singleRegistry.register(FinderConflictBackend(paths: ["one.md"]), kind: .custom)
    let third = ArchiveAppModel(registry: singleRegistry, defaults: defaults)
    try start(third)
    try await waitUntil { third.conflictPrompt != nil }
    third.answerConflict(.keepBoth, remaining: false)
    try await waitForFinishedJob(third)
    #expect(try String(contentsOf: root.appendingPathComponent("one.md"), encoding: .utf8) == "existing-one")
    #expect(try String(contentsOf: root.appendingPathComponent("one 2.md"), encoding: .utf8) == "incoming-one.md")
}

@MainActor
@Test func credentialRetriesPreserveConflictPolicyUntilMaterialization() async throws {
    let suite = "ArchivistTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("ask", forKey: "defaultConflict")

    let registry = ArchiveBackendRegistry()
    let backend = PasswordConflictBackend(correctPassword: "correct")
    await registry.register(backend, kind: .custom)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let archive = root.appendingPathComponent("Encrypted.zip")
    try Data([0x50, 0x4b, 0x03, 0x04]).write(to: archive)
    let existing = root.appendingPathComponent("conflict.txt")
    let original = Data("existing destination content".utf8)
    try original.write(to: existing)

    let model = ArchiveAppModel(registry: registry, defaults: defaults)
    try FinderRequestCoordinator(model: model).route(.init(action: .extractHere, urls: [archive]))
    try await waitUntil { model.passwordPromptVisible }

    // A wrong credential creates another credential-required attempt without changing policy.
    model.password = "wrong"
    model.submitPassword()
    try await waitUntil { model.passwordPromptVisible }
    #expect(try Data(contentsOf: existing) == original)

    // The correct credential must still enter the normal conflict broker before materialization.
    model.password = "correct"
    model.submitPassword()
    try await waitUntil { model.conflictPrompt != nil }
    #expect(try Data(contentsOf: existing) == original)
    #expect(backend.observedConflictPolicies == [.replace]) // backend only writes to isolated staging

    model.answerConflict(.skip, remaining: false)
    try await waitUntil {
        await model.queue.snapshots().contains { if case .completed = $0.state { true } else { false } }
    }
    #expect(try Data(contentsOf: existing) == original)
}

@Test func structuredErrorsBecomeSafePresentation() {
    let result=ErrorPresentation(.init(.corruptedArchive,message:"raw",backendIdentifier:"fake",diagnosticCode:"BAD_ARCHIVE"))
    #expect(result.title == "Archive Appears Corrupted");#expect(result.message.contains("appears to be corrupted"));#expect(result.details == "fake · BAD_ARCHIVE")
}

@MainActor
@Test func appModelCancelsVisibleJob() async throws {
    let model=ArchiveAppModel(registry:.init(),maximumConcurrentJobs:1),descriptor=JobDescriptor(kind:.extract,sourceURLs:[])
    await model.queue.enqueue(descriptor){_ in try await Task.sleep(for:.seconds(30))}
    try await waitUntil { await model.queue.snapshot(descriptor.id)?.state == .running }
    model.cancelJob(descriptor.id)
    try await waitUntil { await model.queue.snapshot(descriptor.id)?.state == .cancelled }
}

@MainActor
@Test func extractionFlowInvokesApplicationAndMaterializesFile() async throws {
    let registry=ArchiveBackendRegistry(),backend=UIFakeBackend();await registry.register(backend,kind:.custom)
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try?FileManager.default.removeItem(at:root)}
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let archive=root.appendingPathComponent("a.zip");try Data([0x50,0x4b,0x03,0x04]).write(to:archive)
    let model=ArchiveAppModel(registry:registry);model.open(archive);try await waitUntil{!model.isScanning}
    let destination=root.appendingPathComponent("out");model.startExtraction(to:destination,selectedOnly:false)
    try await waitUntil{await model.queue.snapshots().contains{$0.descriptor.kind == .extract && $0.state == .completed}}
    #expect(backend.extractCount == 1)
    #expect(try String(contentsOf:destination.appendingPathComponent("folder/file.txt"),encoding:.utf8) == "payload")
}

@Test func previewExtractsOnlyRequestedEntryAndCleansUp() async throws {
    let registry=ArchiveBackendRegistry(),backend=UIFakeBackend();await registry.register(backend,kind:.custom)
    let archive=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
    defer{try?FileManager.default.removeItem(at:archive)};try Data([0x50,0x4b,0x03,0x04]).write(to:archive)
    let entry=ArchiveEntry(path:"folder/file.txt",kind:.regularFile,uncompressedSize:7)
    let artifact=try await PreviewUseCase(registry:registry,filesystem:.init()).execute(.init(archiveURL:archive,entry:entry))
    #expect(try String(contentsOf:artifact.fileURL,encoding:.utf8) == "payload");#expect(artifact.warning != nil)
    let url=artifact.fileURL;artifact.cleanup();#expect(!FileManager.default.fileExists(atPath:url.path))
}

@Test func previewRejectsOversizedEntryBeforeBackendWork() async {
    let request=PreviewRequest(archiveURL:URL(fileURLWithPath:"/missing.zip"),entry:.init(path:"huge",kind:.regularFile,uncompressedSize:100),maximumPreviewBytes:10)
    await #expect(throws:ApplicationError.self){try await PreviewUseCase(registry:.init(),filesystem:.init()).execute(request)}
}

@MainActor private func waitUntil(_ predicate: @escaping @MainActor @Sendable () async -> Bool) async throws {
    for _ in 0..<200 { if await predicate(){return};try await Task.sleep(for:.milliseconds(10)) }
    Issue.record("Timed out")
}

private final class UIFakeBackend:ArchiveBackend,@unchecked Sendable{
    let identifier=BackendIdentifier(rawValue:"ui-fake")
    private let lock=NSLock();private var _extractCount=0
    var extractCount:Int{lock.withLock{_extractCount}}
    func capabilities(for format:ArchiveFormat)->ArchiveCapabilities{format == .zip(.zip) ? .init(operations:[.read,.list,.extract,.create,.test],requiresSequentialScan:true):.unsupported}
    func open(_ url:URL,format:ArchiveFormat,credential:ArchiveCredential?)async throws->ArchiveHandle{.init(backend:identifier,format:format)}
    func list(_ handle:ArchiveHandle)->AsyncThrowingStream<ArchiveEntry,Error>{AsyncThrowingStream{$0.yield(.init(path:"folder",kind:.directory));$0.yield(.init(path:"folder/file.txt",kind:.regularFile));$0.finish()}}
    func extract(_ handle:ArchiveHandle,entries:[ArchiveEntry]?,to destination:URL,options:ExtractionOptions)->AsyncThrowingStream<ProgressEvent,Error>{
        lock.withLock{_extractCount += 1}
        return AsyncThrowingStream{continuation in do{let folder=destination.appendingPathComponent("folder");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try Data("payload".utf8).write(to:folder.appendingPathComponent("file.txt"));continuation.finish()}catch{continuation.finish(throwing:error)}}
    }
    func create(from sources:[URL],to destination:URL,options:CreationOptions)->AsyncThrowingStream<ProgressEvent,Error>{AsyncThrowingStream{$0.finish()}}
    func test(_ handle:ArchiveHandle)->AsyncThrowingStream<ProgressEvent,Error>{AsyncThrowingStream{$0.finish()}}
    func close(_ handle:ArchiveHandle)async{}
}

private final class FinderConflictBackend: ArchiveBackend, @unchecked Sendable {
    let identifier = BackendIdentifier(rawValue: "finder-conflict-fake")
    private let paths: [String]
    private let lock = NSLock()
    private var _lastConflictResolution: ConflictResolution?
    var lastConflictResolution: ConflictResolution? { lock.withLock { _lastConflictResolution } }

    init(paths: [String]) { self.paths = paths }
    func capabilities(for format: ArchiveFormat) -> ArchiveCapabilities {
        format == .zip(.zip) ? .init(operations: [.read, .list, .extract]) : .unsupported
    }
    func open(_ url: URL, format: ArchiveFormat, credential: ArchiveCredential?) async throws -> ArchiveHandle {
        .init(backend: identifier, format: format)
    }
    func list(_ handle: ArchiveHandle) -> AsyncThrowingStream<ArchiveEntry, Error> {
        AsyncThrowingStream { continuation in
            paths.forEach { continuation.yield(.init(path: $0, kind: .regularFile)) }
            continuation.finish()
        }
    }
    func extract(_ handle: ArchiveHandle, entries: [ArchiveEntry]?, to destination: URL,
                 options: ExtractionOptions) -> AsyncThrowingStream<ProgressEvent, Error> {
        lock.withLock { _lastConflictResolution = options.conflictResolution }
        return AsyncThrowingStream { continuation in
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                for path in paths {
                    try Data("incoming-\(path)".utf8).write(to: destination.appendingPathComponent(path))
                }
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }
    func create(from sources: [URL], to destination: URL,
                options: CreationOptions) -> AsyncThrowingStream<ProgressEvent, Error> { .init { $0.finish() } }
    func test(_ handle: ArchiveHandle) -> AsyncThrowingStream<ProgressEvent, Error> { .init { $0.finish() } }
    func close(_ handle: ArchiveHandle) async {}
}

private final class PasswordConflictBackend: ArchiveBackend, @unchecked Sendable {
    let identifier = BackendIdentifier(rawValue: "password-conflict-fake")
    private let correctPassword: String
    private let lock = NSLock()
    private var policies: [ConflictResolution] = []
    var observedConflictPolicies: [ConflictResolution] { lock.withLock { policies } }

    init(correctPassword: String) { self.correctPassword = correctPassword }
    func capabilities(for format: ArchiveFormat) -> ArchiveCapabilities {
        format == .zip(.zip) ? .init(operations: [.read, .list, .extract]) : .unsupported
    }
    func open(_ url: URL, format: ArchiveFormat, credential: ArchiveCredential?) async throws -> ArchiveHandle {
        guard credential?.password == correctPassword else {
            throw ArchiveBackendError(.incorrectPassword, backendIdentifier: identifier.rawValue,
                                      message: "Credential required", diagnosticCode: "TEST_PASSWORD")
        }
        return .init(backend: identifier, format: format)
    }
    func list(_ handle: ArchiveHandle) -> AsyncThrowingStream<ArchiveEntry, Error> {
        .init { continuation in
            continuation.yield(.init(path: "conflict.txt", kind: .regularFile))
            continuation.finish()
        }
    }
    func extract(_ handle: ArchiveHandle, entries: [ArchiveEntry]?, to destination: URL,
                 options: ExtractionOptions) -> AsyncThrowingStream<ProgressEvent, Error> {
        lock.withLock { policies.append(options.conflictResolution) }
        return .init { continuation in
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try Data("incoming encrypted content".utf8)
                    .write(to: destination.appendingPathComponent("conflict.txt"))
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }
    func create(from sources: [URL], to destination: URL,
                options: CreationOptions) -> AsyncThrowingStream<ProgressEvent, Error> { .init { $0.finish() } }
    func test(_ handle: ArchiveHandle) -> AsyncThrowingStream<ProgressEvent, Error> { .init { $0.finish() } }
    func close(_ handle: ArchiveHandle) async {}
}

@MainActor private final class PresentationSpy: ApplicationPresenting {
    var mainWindowCount = 0
    var jobsCount = 0
    var destinationArchive: URL?
    func presentMainWindow() { mainWindowCount += 1 }
    func presentJobs() { jobsCount += 1 }
    func presentExtractionDestination(for archive: URL, completion: @escaping @MainActor (URL) -> Void) { destinationArchive = archive }
}
@Test func archivistPreferenceMigrationCopiesOnlyKnownKeysOnce() throws {
    let sourceSuite = "ArchivistMigrationSource.\(UUID().uuidString)"
    let destinationSuite = "ArchivistMigrationDestination.\(UUID().uuidString)"
    let domains = try #require(UserDefaults(suiteName: sourceSuite))
    let destination = try #require(UserDefaults(suiteName: destinationSuite))
    defer { domains.removePersistentDomain(forName: ArchivistPreferenceMigration.sourceDomain); destination.removePersistentDomain(forName: destinationSuite) }
    domains.setPersistentDomain([
        "defaultConflict": "skip",
        "preventPathTraversal": false,
        "unrelated": "do-not-copy"
    ], forName: ArchivistPreferenceMigration.sourceDomain)

    ArchivistPreferenceMigration.migrateIfNeeded(destination: destination, persistentDomains: domains)
    #expect(destination.string(forKey: "defaultConflict") == "skip")
    #expect(destination.object(forKey: "preventPathTraversal") as? Bool == false)
    #expect(destination.object(forKey: "unrelated") == nil)

    domains.setPersistentDomain(["defaultConflict": "replace"], forName: ArchivistPreferenceMigration.sourceDomain)
    ArchivistPreferenceMigration.migrateIfNeeded(destination: destination, persistentDomains: domains)
    #expect(destination.string(forKey: "defaultConflict") == "skip")
}
