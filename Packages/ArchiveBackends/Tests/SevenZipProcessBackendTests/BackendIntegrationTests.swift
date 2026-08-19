import BackendProtocol
import Domain
import Foundation
import Testing

@Test func passwordRequirementOutputIsDistinguishedFromCrash() {
    #expect(SevenZipPasswordRequirementDetector.requiresCredential("Enter password (will not be echoed):"))
    #expect(SevenZipPasswordRequirementDetector.requiresCredential("ERROR: Password is not defined"))
    #expect(!SevenZipPasswordRequirementDetector.requiresCredential("Segmentation fault"))
}
@testable import SevenZipProcessBackend

@Test func productionBackendCreatesListsTestsAndExtracts() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SEVENZIP_TEST_EXECUTABLE"])
    let backend = try await SevenZipProcessBackend(locator: .init(source: .external(URL(fileURLWithPath: path))))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("backend-test-\(UUID())")
    let sourceDir = root.appendingPathComponent("source folder"), nested = sourceDir.appendingPathComponent("日本語")
    let file = nested.appendingPathComponent("Türkçe 📦.txt"), archive = root.appendingPathComponent("archive file.7z"), output = root.appendingPathComponent("out")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true); try Data("payload".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: root) }
    for try await _ in backend.create(from: [sourceDir], to: archive, options: .init(format: .sevenZip)) {}
    let handle = try await backend.open(archive, format: .sevenZip, credential: nil)
    var entries: [ArchiveEntry] = []; for try await entry in backend.list(handle) { entries.append(entry) }
    #expect(entries.contains { $0.path.contains("Türkçe 📦.txt") })
    for try await _ in backend.test(handle) {}
    for try await _ in backend.extract(handle, entries: nil, to: output, options: .init()) {}
    #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("source folder/日本語/Türkçe 📦.txt").path))
    await backend.close(handle)
    await backend.close(handle)
}
