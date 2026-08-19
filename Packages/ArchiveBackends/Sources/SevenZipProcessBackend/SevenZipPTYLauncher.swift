import CPTYShim
import Darwin
import Foundation

public struct SevenZipPTYResult: Sendable {
    public let exitCode: Int32?
    public let terminationSignal: Int32?
    public let output: String
    public let cancellationRequested: Bool
}

private actor PTYProcessController {
    private var pid: pid_t?
    private var cancellationRequested = false
    func register(pid: pid_t) { self.pid = pid; if cancellationRequested { _ = az_pty_signal(pid, SIGTERM) } }
    func cancel() { cancellationRequested = true; if let pid { _ = az_pty_signal(pid, SIGTERM) } }
    func wasCancelled() -> Bool { cancellationRequested }
}

public struct SevenZipPTYLauncher: Sendable {
    public init() {}
    public func run(executable: URL, arguments: [String], secret: SecretBytes,
                    diagnosticLimit: Int = 65_536,
                    onSpawn: @escaping @Sendable (pid_t) -> Void = { _ in }) async throws -> SevenZipPTYResult {
        let controller = PTYProcessController()
        return try await withTaskCancellationHandler {
            try await Task.detached {
                try await runBlocking(executable: executable, arguments: arguments, secret: secret,
                                      diagnosticLimit: diagnosticLimit, controller: controller, onSpawn: onSpawn)
            }.value
        } onCancel: { Task { await controller.cancel() } }
    }

    private func runBlocking(executable: URL, arguments: [String], secret: SecretBytes,
                             diagnosticLimit: Int, controller: PTYProcessController,
                             onSpawn: @escaping @Sendable (pid_t) -> Void) async throws -> SevenZipPTYResult {
        let cStrings = ([executable.path] + arguments).map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var argv = cStrings + [nil], pid: pid_t = 0, master: Int32 = -1
        let spawnResult = executable.path.withCString { az_pty_spawn($0, &argv, &pid, &master) }
        guard spawnResult == 0 else { throw POSIXError(.init(rawValue: spawnResult) ?? .EIO) }
        await controller.register(pid: pid)
        onSpawn(pid)
        defer { close(master) }
        guard az_pty_set_nonblocking(master) == 0 else { _ = az_pty_signal(pid, SIGKILL); var status: Int32 = 0; _ = az_pty_wait(pid, &status, 0); throw POSIXError(.EIO) }
        var parser = SevenZipInteractivePromptParser(), capture = BoundedTerminalCapture(limit: diagnosticLimit)
        var secretSent = false, status: Int32 = 0, graceStart: ContinuousClock.Instant?
        let clock = ContinuousClock()
        while true {
            var pollDescriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            _ = Darwin.poll(&pollDescriptor, 1, 100)
            if pollDescriptor.revents & Int16(POLLIN) != 0 {
                var raw = [UInt8](repeating: 0, count: 4096)
                let count = read(master, &raw, raw.count)
                if count > 0 {
                    let chunk = Data(raw.prefix(count)); capture.append(chunk)
                    if !secretSent && parser.consume(chunk) {
                        try secret.withUnsafeBytes { bytes in
                            guard let base = bytes.baseAddress else { throw POSIXError(.EINVAL) }
                            if write(master, base, bytes.count) != bytes.count { throw POSIXError(.EIO) }
                        }
                        var newline: UInt8 = 0x0A
                        guard write(master, &newline, 1) == 1 else { throw POSIXError(.EIO) }
                        secretSent = true
                    }
                }
            }
            let wait = az_pty_wait(pid, &status, WNOHANG)
            if wait == pid { break }
            if await controller.wasCancelled() {
                if graceStart == nil { graceStart = clock.now }
                if let graceStart, clock.now - graceStart > .seconds(2) { _ = az_pty_signal(pid, SIGKILL) }
            }
        }
        return .init(exitCode: az_pty_status_exited(status) != 0 ? az_pty_status_exit_code(status) : nil,
                     terminationSignal: az_pty_status_signaled(status) != 0 ? az_pty_status_signal(status) : nil,
                     output: capture.text, cancellationRequested: await controller.wasCancelled())
    }
}
