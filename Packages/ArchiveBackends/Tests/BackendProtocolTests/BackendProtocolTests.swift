import BackendProtocol
import Domain
import Foundation
import Testing

private struct MockBackend: ArchiveBackend {
    let identifier = BackendIdentifier(rawValue: "mock")
    func capabilities(for format: ArchiveFormat) -> ArchiveCapabilities { .init(operations: [.read, .list]) }
    func open(_ url: URL, format: ArchiveFormat, credential: ArchiveCredential?) async throws -> ArchiveHandle { .init(backend: identifier, format: format) }
    func list(_ handle: ArchiveHandle) -> AsyncThrowingStream<ArchiveEntry, Error> {
        AsyncThrowingStream { continuation in continuation.yield(.init(path: "file", kind: .regularFile)); continuation.finish() }
    }
    func extract(_ handle: ArchiveHandle, entries: [ArchiveEntry]?, to destination: URL, options: ExtractionOptions) -> AsyncThrowingStream<ProgressEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func create(from sources: [URL], to destination: URL, options: CreationOptions) -> AsyncThrowingStream<ProgressEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func test(_ handle: ArchiveHandle) -> AsyncThrowingStream<ProgressEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func close(_ handle: ArchiveHandle) async {}
}

@Test func consumerUsesBackendWithoutImplementationKnowledge() async throws {
    let backend: any ArchiveBackend = MockBackend()
    let handle = try await backend.open(URL(fileURLWithPath: "/tmp/a"), format: .sevenZip, credential: nil)
    var entries: [ArchiveEntry] = []
    for try await entry in backend.list(handle) { entries.append(entry) }
    #expect(entries.map(\.path) == ["file"])
    #expect(backend.capabilities(for: .sevenZip).supports(.list))
}

@Test func credentialsAlwaysDescribeAsRedacted() {
    let credential = ArchiveCredential(password: "top-secret")
    #expect(String(describing: credential) == "<redacted>")
    #expect(String(reflecting: credential) == "ArchiveCredential(<redacted>)")
}

@Test func handleOwnershipIsEnforced() {
    let backend = MockBackend()
    let foreign = ArchiveHandle(backend: .init(rawValue: "other"), format: .zip(.zip))
    #expect(throws: ArchiveBackendError.self) { try backend.requireOwnedHandle(foreign) }
}

@Test func creationCapabilitiesAreFormatSpecificAndValidationRejectsInvalidCombinations() throws {
    let sevenZip = try #require(AuthoritativeCapabilities.capabilities(for: .sevenZip, backend: .sevenZip).creationOptions)
    let zip = try #require(AuthoritativeCapabilities.capabilities(for: .zip(.zip), backend: .sevenZip).creationOptions)
    let tar = try #require(AuthoritativeCapabilities.capabilities(for: .tar, backend: .libarchive).creationOptions)
    #expect(sevenZip.supportsSolid); #expect(sevenZip.supportsHeaderEncryption)
    #expect(!zip.supportsSolid); #expect(!zip.supportsHeaderEncryption)
    #expect(tar.compressionLevels.isEmpty && tar.methods.isEmpty)

    #expect(throws: CreationOptionsValidationError.headerEncryptionRequiresPassword) {
        try CreationOptions(format: .sevenZip, encryptFileNames: true).validate(against: sevenZip)
    }
    #expect(throws: CreationOptionsValidationError.unsupportedMethod) {
        try CreationOptions(format: .zip(.zip), method: .lzma2).validate(against: zip)
    }
    #expect(throws: CreationOptionsValidationError.threadCountOutOfRange) {
        try CreationOptions(format: .sevenZip, threads: .explicit(65)).validate(against: sevenZip, logicalProcessorCount: 128)
    }
}
