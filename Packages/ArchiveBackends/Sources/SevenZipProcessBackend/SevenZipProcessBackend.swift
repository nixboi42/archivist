import BackendProtocol
import Domain
import Foundation

private struct SevenZipSession: Sendable { let url: URL; let format: ArchiveFormat; let credential: SecretBytes? }
private actor SevenZipSessionRegistry {
    private var sessions: [UUID: SevenZipSession] = [:]
    func insert(_ handle: ArchiveHandle, session: SevenZipSession) { sessions[handle.id] = session }
    func session(for handle: ArchiveHandle) throws -> SevenZipSession {
        guard let session = sessions[handle.id] else { throw ArchiveBackendError(.backendFailure, backendIdentifier: "7zz", message: "Unknown or closed archive handle", diagnosticCode: "INVALID_HANDLE") }
        return session
    }
    func remove(_ handle: ArchiveHandle) { sessions.removeValue(forKey: handle.id) }
}

public final class SevenZipProcessBackend: ArchiveBackend, Sendable {
    public let identifier = BackendIdentifier(rawValue: "7zz")
    private let executable: URL
    private let sessions = SevenZipSessionRegistry()
    private let normal = SevenZipProcessRunner(), secure = SevenZipPTYLauncher(), builder = SevenZipArgumentBuilder()

    public init(locator: SevenZipExecutableLocator) async throws {
        let executable = try locator.locate()
        let probe = try await SevenZipProcessRunner().run(executable: executable, arguments: ["i"])
        guard probe.exitCode == 0, probe.output.contains("7-Zip"), probe.output.lowercased().contains("arm64") else {
            throw ArchiveBackendError(.backendUnavailable, backendIdentifier: "7zz", message: "Executable failed the 7zz arm64 contract probe")
        }
        self.executable = executable
    }

    public func capabilities(for format: ArchiveFormat) -> ArchiveCapabilities { SevenZipCapabilities.capabilities(for: format) }

    public func open(_ url: URL, format: ArchiveFormat, credential: ArchiveCredential?) async throws -> ArchiveHandle {
        guard capabilities(for: format).supports(.read) else { throw ArchiveBackendError(.unsupportedOperation, backendIdentifier: identifier.rawValue, operation: .read, message: "Unsupported format") }
        try Self.preflightMultipartSequence(url)
        let handle = ArchiveHandle(backend: identifier, format: format)
        await sessions.insert(handle, session: .init(url: url, format: format, credential: credential.map { SecretBytes($0.password) }))
        return handle
    }

    private static func preflightMultipartSequence(_ url: URL) throws {
        guard let multipart = MultipartArchiveName.parse(url.lastPathComponent), multipart.isFirstVolume else { return }
        let parent = url.deletingLastPathComponent(), prefix = multipart.baseFilename + "."
        let numbers = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            .compactMap { candidate -> Int? in
                guard candidate.lastPathComponent.hasPrefix(prefix) else { return nil }
                let suffix = candidate.lastPathComponent.dropFirst(prefix.count)
                guard suffix.count == 3, suffix.allSatisfy(\.isNumber) else { return nil }
                return Int(suffix)
            }
        guard let maximum = numbers.max(), Set(numbers) == Set(1...maximum) else {
            throw missingVolumeError(.read)
        }
    }

    public func list(_ handle: ArchiveHandle) -> AsyncThrowingStream<ArchiveEntry, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try requireOwnedHandle(handle); let session = try await sessions.session(for: handle)
                    let args = try builder.build(.list(session.url), hasCredential: session.credential != nil)
                    let output = try await execute(args, credential: session.credential, operation: .list)
                    for entry in SevenZipListingParser().parse(output) { continuation.yield(entry) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func extract(_ handle: ArchiveHandle, entries: [ArchiveEntry]?, to destination: URL, options: ExtractionOptions) -> AsyncThrowingStream<ProgressEvent, Error> {
        progressStream(operation: .extract, phase: .extracting) {
            try self.requireOwnedHandle(handle); let session = try await self.sessions.session(for: handle)
            let credential = options.credential.map { SecretBytes($0.password) } ?? session.credential
            return try self.builder.build(.extract(session.url, destination, entries?.map(\.path)), hasCredential: credential != nil).withCredential(credential)
        }
    }

    public func create(from sources: [URL], to destination: URL, options: CreationOptions) -> AsyncThrowingStream<ProgressEvent, Error> {
        progressStream(operation: .create, phase: .creating) {
            guard self.capabilities(for: options.format).supports(.create) else { throw ArchiveBackendError(.unsupportedOperation, backendIdentifier: "7zz", operation: .create, message: "Creation disabled") }
            let credential = options.credential.map { SecretBytes($0.password) }
            return try self.builder.build(.create(sources, destination, options), hasCredential: credential != nil).withCredential(credential)
        }
    }

    public func test(_ handle: ArchiveHandle) -> AsyncThrowingStream<ProgressEvent, Error> {
        progressStream(operation: .test, phase: .testing) {
            try self.requireOwnedHandle(handle); let session = try await self.sessions.session(for: handle)
            return try self.builder.build(.test(session.url), hasCredential: session.credential != nil).withCredential(session.credential)
        }
    }

    public func close(_ handle: ArchiveHandle) async { guard handle.backend == identifier else { return }; await sessions.remove(handle) }

    private func execute(_ args: SevenZipArguments, credential: SecretBytes?, operation: ArchiveOperation) async throws -> String {
        if let credential {
            let result = try await secure.run(executable: executable, arguments: args.values, secret: credential)
            if Self.indicatesMissingVolume(result.output) { throw Self.missingVolumeError(operation) }
            if result.exitCode == 2 && result.output.localizedCaseInsensitiveContains("wrong password") {
                throw ArchiveBackendError(.incorrectPassword, backendIdentifier: "7zz", operation: operation,
                                          message: "The archive credential was rejected", diagnosticCode: "CREDENTIAL_REJECTED")
            }
            if let error = SevenZipExitCodeMapper().error(exitCode: result.exitCode, signal: result.terminationSignal, cancellationRequested: result.cancellationRequested, operation: operation) { throw error }
            return result.output
        }
        let result = try await normal.run(executable: executable, arguments: args.values)
        if Self.indicatesMissingVolume(result.output) { throw Self.missingVolumeError(operation) }
        if result.exitCode == 255 && SevenZipPasswordRequirementDetector.requiresCredential(result.output) {
            throw ArchiveBackendError(.incorrectPassword, backendIdentifier: "7zz", operation: operation,
                                      message: "The archive requires a credential", diagnosticCode: "CREDENTIAL_REQUIRED")
        }
        if let error = SevenZipExitCodeMapper().error(exitCode: result.exitCode, signal: nil, cancellationRequested: result.cancellationRequested, operation: operation) { throw error }
        return result.output
    }

    private static func indicatesMissingVolume(_ output: String) -> Bool {
        output.localizedCaseInsensitiveContains("missing volume") ||
        output.localizedCaseInsensitiveContains("unexpected end of archive") && output.localizedCaseInsensitiveContains(".00")
    }
    private static func missingVolumeError(_ operation: ArchiveOperation) -> ArchiveBackendError {
        .init(.corruptedArchive, backendIdentifier: "7zz", operation: operation,
              message: "A required multipart archive volume is missing", diagnosticCode: "MISSING_ARCHIVE_VOLUME")
    }

    private func progressStream(operation: ArchiveOperation, phase: ProgressEvent.Phase,
                                build: @escaping @Sendable () async throws -> CredentialedArguments) -> AsyncThrowingStream<ProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let command = try await build(), output = try await execute(command.arguments, credential: command.credential, operation: operation)
                    var parser = SevenZipProgressParser()
                    for event in parser.consume(Data(output.utf8), phase: phase) { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public enum SevenZipPasswordRequirementDetector {
    public static func requiresCredential(_ output: String) -> Bool {
        let normalized = output.lowercased()
        return normalized.contains("enter password") || normalized.contains("password is not defined")
    }
}

private struct CredentialedArguments: Sendable { let arguments: SevenZipArguments; let credential: SecretBytes? }
private extension SevenZipArguments { func withCredential(_ credential: SecretBytes?) -> CredentialedArguments { .init(arguments: self, credential: credential) } }
