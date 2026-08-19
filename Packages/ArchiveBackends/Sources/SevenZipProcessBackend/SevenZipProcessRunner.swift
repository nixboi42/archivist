import Darwin
import Foundation

public struct SevenZipProcessResult: Sendable { public let exitCode: Int32; public let output: String; public let diagnostics: String; public let cancellationRequested: Bool }

private final class LockedCapture: @unchecked Sendable {
    // FileHandle callbacks may execute concurrently; every byte and flag is protected by this lock.
    private let lock = NSLock(); private var out = Data(), err = Data(); private let limit: Int
    init(limit: Int) { self.limit = limit }
    func append(_ data: Data, error: Bool) { lock.withLock { if error { err.append(data); if err.count > limit { err.removeFirst(err.count-limit) } } else { out.append(data) } } }
    func snapshot() -> (Data, Data) { lock.withLock { (out, err) } }
}

private actor NormalProcessController {
    private var process: Process?; private var cancelled = false
    func register(_ process: Process) { self.process = process; if cancelled { process.terminate() } }
    func cancel() { cancelled = true; process?.terminate() }
    func wasCancelled() -> Bool { cancelled }
}

public struct SevenZipProcessRunner: Sendable {
    public init() {}
    public func run(executable: URL, arguments: [String], diagnosticLimit: Int = 65_536) async throws -> SevenZipProcessResult {
        let controller = NormalProcessController()
        return try await withTaskCancellationHandler {
            try await Task.detached {
                let process = Process(), stdout = Pipe(), stderr = Pipe(), capture = LockedCapture(limit: diagnosticLimit)
                process.executableURL = executable; process.arguments = arguments; process.standardOutput = stdout; process.standardError = stderr
                stdout.fileHandleForReading.readabilityHandler = { let d = $0.availableData; if !d.isEmpty { capture.append(d, error: false) } }
                stderr.fileHandleForReading.readabilityHandler = { let d = $0.availableData; if !d.isEmpty { capture.append(d, error: true) } }
                try process.run(); await controller.register(process); process.waitUntilExit()
                stdout.fileHandleForReading.readabilityHandler = nil; stderr.fileHandleForReading.readabilityHandler = nil
                capture.append(stdout.fileHandleForReading.readDataToEndOfFile(), error: false)
                capture.append(stderr.fileHandleForReading.readDataToEndOfFile(), error: true)
                let data = capture.snapshot()
                return .init(exitCode: process.terminationStatus, output: String(decoding: data.0, as: UTF8.self),
                             diagnostics: String(decoding: data.1, as: UTF8.self), cancellationRequested: await controller.wasCancelled())
            }.value
        } onCancel: { Task { await controller.cancel() } }
    }
}
