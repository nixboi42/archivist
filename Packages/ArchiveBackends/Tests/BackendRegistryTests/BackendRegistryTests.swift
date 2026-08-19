import BackendProtocol
import BackendRegistry
import Domain
import Foundation
import Testing

private final class MockBackend: ArchiveBackend, Sendable {
    let identifier: BackendIdentifier
    let supported: [ArchiveFormat: ArchiveCapabilities]
    init(_ identifier: String, _ supported: [ArchiveFormat: ArchiveCapabilities]) { self.identifier = .init(rawValue: identifier); self.supported = supported }
    func capabilities(for format: ArchiveFormat) -> ArchiveCapabilities { supported[format] ?? .unsupported }
    func open(_ url: URL, format: ArchiveFormat, credential: ArchiveCredential?) async throws -> ArchiveHandle { .init(backend: identifier, format: format) }
    func list(_ handle: ArchiveHandle) -> AsyncThrowingStream<ArchiveEntry, Error> { .init { $0.finish() } }
    func extract(_ handle: ArchiveHandle, entries: [ArchiveEntry]?, to destination: URL, options: ExtractionOptions) -> AsyncThrowingStream<ProgressEvent, Error> { .init { $0.finish() } }
    func create(from sources: [URL], to destination: URL, options: CreationOptions) -> AsyncThrowingStream<ProgressEvent, Error> { .init { $0.finish() } }
    func test(_ handle: ArchiveHandle) -> AsyncThrowingStream<ProgressEvent, Error> { .init { $0.finish() } }
    func close(_ handle: ArchiveHandle) async {}
}

private let zipRead = ArchiveCapabilities(operations: [.read, .list, .extract])

@Test func explicitPolicySelectsPrimaryNotRegistrationOrder() async throws {
    let registry=ArchiveBackendRegistry(),fallback=MockBackend("libarchive",[.zip(.zip):zipRead]),primary=MockBackend("7zz",[.zip(.zip):zipRead])
    await registry.register(fallback,kind:.custom);await registry.register(primary,kind:.custom)
    let selected=try await registry.select(format:.zip(.zip),operation:.read)
    #expect(selected.backend.identifier.rawValue=="7zz");#expect(!selected.usedFallback)
}

@Test func fallbackSelectedWhenPrimaryUnavailable() async throws {
    let registry=ArchiveBackendRegistry(),fallback=MockBackend("libarchive",[.zip(.zip):zipRead])
    await registry.registerUnavailable(identifier:.init(rawValue:"7zz"),kind:.sevenZip,reason:"helper missing")
    await registry.register(fallback,kind:.custom)
    let selected=try await registry.select(format:.zip(.zip),operation:.read)
    #expect(selected.backend.identifier.rawValue=="libarchive");#expect(selected.usedFallback)
}

@Test func unsupportedAndUnknownOperationsAreRejected() async throws {
    let registry=ArchiveBackendRegistry();await registry.register(MockBackend("7zz",[.zip(.zip):zipRead]),kind:.custom)
    await #expect(throws:ArchiveBackendError.self){try await registry.select(format:.zip(.zip),operation:.create)}
    do{_ = try await registry.select(format:.unknown,operation:.read);Issue.record("Expected unknown format rejection")}catch let error as ArchiveBackendError{#expect(error.code == .unsupportedFormat)}
}

@Test func unavailableBackendIsNeverSelected() async throws {
    let registry=ArchiveBackendRegistry();await registry.registerUnavailable(identifier:.init(rawValue:"7zz"),kind:.sevenZip,reason:"probe failed")
    do{_ = try await registry.select(format:.sevenZip,operation:.read);Issue.record("Expected unavailable failure")}catch let error as ArchiveBackendError{#expect(error.code == .noAvailableBackend)}
}

@Test func unknownCapabilityStaysDisabled() async throws {
    let registry=ArchiveBackendRegistry();await registry.register(MockBackend("mystery",[.unknown:.init(operations:[.read])]),kind:.custom)
    await #expect(throws:ArchiveBackendError.self){try await registry.select(format:.unknown,operation:.read)}
}

@Test func duplicateInstancesCannotCreateNondeterministicOrdering() async throws {
    let registry=ArchiveBackendRegistry(),first=MockBackend("7zz",[.zip(.zip):zipRead]),replacement=MockBackend("7zz",[.zip(.zip):zipRead])
    await registry.register(first,kind:.custom);await registry.register(replacement,kind:.custom)
    #expect(await registry.statuses().count==1)
    for _ in 0..<20 { #expect(try await registry.select(format:.zip(.zip),operation:.read).backend.identifier.rawValue=="7zz") }
}

@Test func preferredOnlyReportsPreferredBackendFailure() async throws {
    let registry=ArchiveBackendRegistry();await registry.registerUnavailable(identifier:.init(rawValue:"7zz"),kind:.sevenZip,reason:"missing")
    await registry.register(MockBackend("libarchive",[.zip(.zip):zipRead]),kind:.custom)
    do{_ = try await registry.select(format:.zip(.zip),operation:.read,mode:.preferredOnly);Issue.record("Expected preferred failure")}catch let error as ArchiveBackendError{#expect(error.code == .preferredBackendUnavailable)}
}
