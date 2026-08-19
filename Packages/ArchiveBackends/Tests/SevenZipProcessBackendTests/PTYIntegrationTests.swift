import Foundation
import Darwin
import CPTYShim
import Testing
@testable import SevenZipProcessBackend

private let fakeSecret = "TEST_SECRET_DO_NOT_LEAK_847291"

private func executable() throws -> URL {
    let path = try #require(ProcessInfo.processInfo.environment["SEVENZIP_TEST_EXECUTABLE"])
    let url = URL(fileURLWithPath: path)
    #expect(FileManager.default.isExecutableFile(atPath: path))
    return url
}

@Test func encryptedCreationAndExtractionUsePTYWithoutLeakage() async throws {
    let sevenZip = try executable(), root = FileManager.default.temporaryDirectory.appendingPathComponent("pty-test-\(UUID())")
    let source = root.appendingPathComponent("Türkçe 📦 input.txt"), archive = root.appendingPathComponent("encrypted archive.7z")
    let output = root.appendingPathComponent("output")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("payload".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: root) }
    let launcher = SevenZipPTYLauncher(), secret = SecretBytes(fakeSecret)
    let created = try await launcher.run(executable: sevenZip,
        arguments: ["a", "-t7z", "-p", "-mhe=on", archive.path, "--", source.path], secret: secret)
    #expect(created.exitCode == 0); #expect(!created.output.contains(fakeSecret))
    let tested = try await launcher.run(executable: sevenZip, arguments: ["t", archive.path], secret: secret)
    #expect(tested.exitCode == 0); #expect(!tested.output.contains(fakeSecret))
    let extracted = try await launcher.run(executable: sevenZip, arguments: ["x", "-y", "-o\(output.path)", archive.path], secret: secret)
    #expect(extracted.exitCode == 0); #expect(!extracted.output.contains(fakeSecret))
    #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent(source.lastPathComponent).path))
}

@Test func wrongSecretDoesNotLeak() async throws {
    let sevenZip = try executable(), root = FileManager.default.temporaryDirectory.appendingPathComponent("pty-wrong-\(UUID())")
    let source = root.appendingPathComponent("file"), archive = root.appendingPathComponent("a.7z")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try Data("payload".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: root) }
    let launcher = SevenZipPTYLauncher()
    #expect((try await launcher.run(executable: sevenZip, arguments: ["a", "-t7z", "-p", "-mhe=on", archive.path, source.path], secret: .init(fakeSecret))).exitCode == 0)
    let wrong = try await launcher.run(executable: sevenZip, arguments: ["t", archive.path], secret: .init("WRONG_SECRET_DO_NOT_LEAK"))
    #expect(wrong.exitCode != 0); #expect(!wrong.output.contains("WRONG_SECRET_DO_NOT_LEAK"))
}

@Test func cancellationReapsChildAndMapsIntent() async throws {
    let sevenZip = try executable(), task = Task {
        try await SevenZipPTYLauncher().run(executable: sevenZip, arguments: ["b", "-mmt1"], secret: .init(fakeSecret))
    }
    try await Task.sleep(for: .milliseconds(100)); task.cancel()
    let result = try await task.value
    #expect(result.cancellationRequested); #expect(result.terminationSignal != nil)
    #expect(!result.output.contains(fakeSecret))
}

private final class PIDBox: @unchecked Sendable {
    private let lock = NSLock(); private var value: pid_t?
    func set(_ pid: pid_t) { lock.withLock { value = pid } }
    func get() -> pid_t? { lock.withLock { value } }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock(); private var value = Data()
    func set(_ data: Data) { lock.withLock { value = data } }
    func get() -> Data { lock.withLock { value } }
}

@Test func liveChildArgvDoesNotContainSecret() async throws {
    let sevenZip = try executable(), box = PIDBox(), argsBox = DataBox()
    let task = Task { try await SevenZipPTYLauncher().run(executable: sevenZip, arguments: ["b", "-mmt1"],
        secret: .init(fakeSecret), onSpawn: { pid in
            box.set(pid); var bytes = [UInt8](repeating: 0, count: 65_536), size = bytes.count
            if az_pty_read_process_args(pid, &bytes, &size) == 0 { argsBox.set(Data(bytes.prefix(size))) }
        }) }
    while box.get() == nil { try await Task.sleep(for: .milliseconds(10)) }
    let command = String(decoding: argsBox.get(), as: UTF8.self)
    #expect(!command.isEmpty)
    #expect(!command.contains(fakeSecret)); #expect(!command.contains("-p" + fakeSecret))
    task.cancel(); _ = try await task.value
}

@Test func externalKillIsNotCancellation() async throws {
    let sevenZip = try executable(), box = PIDBox()
    let task = Task { try await SevenZipPTYLauncher().run(executable: sevenZip, arguments: ["b", "-mmt1"],
                                                          secret: .init(fakeSecret), onSpawn: { box.set($0) }) }
    while box.get() == nil { try await Task.sleep(for: .milliseconds(10)) }
    _ = Darwin.kill(box.get()!, SIGKILL)
    let result = try await task.value
    #expect(!result.cancellationRequested); #expect(result.terminationSignal == SIGKILL)
}
