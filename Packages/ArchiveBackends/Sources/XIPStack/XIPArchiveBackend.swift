import ArchiveSecurity
import BackendProtocol
import Domain
import Foundation

private struct XIPBackendSession: Sendable {
    let url: URL
    let format: ArchiveFormat
    let entries: [ArchiveEntry]
    var verification: ArchiveVerificationDetails?
}

private actor XIPBackendSessions {
    private var values: [UUID: XIPBackendSession] = [:]
    func insert(_ handle: ArchiveHandle, session: XIPBackendSession) { values[handle.id] = session }
    func get(_ handle: ArchiveHandle) throws -> XIPBackendSession {
        guard let value = values[handle.id] else {
            throw ArchiveBackendError(.backendFailure, backendIdentifier: "xip-stack",
                                      message: "Unknown or closed XIP handle", diagnosticCode: "INVALID_HANDLE")
        }
        return value
    }
    func setVerification(_ details: ArchiveVerificationDetails, for handle: ArchiveHandle) {
        guard var value = values[handle.id] else { return }
        value.verification = details; values[handle.id] = value
    }
    func remove(_ handle: ArchiveHandle) { values.removeValue(forKey: handle.id) }
}

public final class XIPArchiveBackend: DetailedVerificationProviding, Sendable {
    public let identifier = BackendIdentifier(rawValue: "xip-stack")
    private let sessions = XIPBackendSessions()
    private let coordinator = XIPCoordinator()
    private let xar = XARInspector()
    private let apple = AppleArchivePayloadReader()
    private let tools = SystemToolRunner()

    public init() {}

    public func capabilities(for format: ArchiveFormat) -> ArchiveCapabilities {
        AuthoritativeCapabilities.capabilities(for: format, backend: .xipStack)
    }

    public func open(_ url: URL, format: ArchiveFormat, credential: ArchiveCredential?) async throws -> ArchiveHandle {
        guard credential == nil else { throw unsupported(.read, "Encrypted credentials are not supported by the XIP stack") }
        guard capabilities(for: format).supports(.read) else { throw unsupported(.read, "Unsupported XIP-stack format") }
        do {
            let entries: [ArchiveEntry]
            let verification: ArchiveVerificationDetails?
            switch format {
            case .xip:
                let inspection = try coordinator.inspect(url)
                try coordinator.requireSupportedPayload(inspection)
                entries = inspection.payloadEntries.map { .init(path: $0.path, kind: kind(for: $0.typeDescription)) }
                verification = inspection.verification.domainDetails
            case .xar:
                entries = try xar.inspect(url).entries.map {
                    .init(path: $0.path, kind: xarKind($0.kind), uncompressedSize: $0.size)
                }
                verification = nil
            case .appleArchive:
                entries = try apple.list(url).map { .init(path: $0.path, kind: kind(for: $0.typeDescription)) }
                verification = nil
            default: throw unsupported(.read, "Unsupported XIP-stack format")
            }
            let handle = ArchiveHandle(backend: identifier, format: format)
            await sessions.insert(handle, session: .init(url: url, format: format, entries: entries, verification: verification))
            return handle
        } catch { throw map(error, operation: .read) }
    }

    public func list(_ handle: ArchiveHandle) -> AsyncThrowingStream<ArchiveEntry, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try requireOwnedHandle(handle)
                    for entry in try await sessions.get(handle).entries {
                        try Task.checkCancellation(); continuation.yield(entry)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: map(error, operation: .list)) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func extract(_ handle: ArchiveHandle, entries: [ArchiveEntry]?, to destination: URL,
                        options: ExtractionOptions) -> AsyncThrowingStream<ProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try requireOwnedHandle(handle); let session = try await sessions.get(handle)
                    try Task.checkCancellation()
                    switch session.format {
                    case .xip:
                        try coordinator.expand(session.url, to: destination, securityPolicy: options.securityPolicy)
                    case .xar:
                        var arguments = ["-xf", session.url.path, "-C", destination.path]
                        arguments.append(contentsOf: entries?.map(\.path) ?? [])
                        let result = try tools.run("/usr/bin/xar", arguments)
                        guard result.status == 0 else { throw XIPStackError.systemToolFailure(tool: "xar", status: result.status, message: result.stderr) }
                    case .appleArchive:
                        let result = try tools.run("/usr/bin/aa", ["extract", "-i", session.url.path, "-d", destination.path])
                        guard result.status == 0 else { throw XIPStackError.systemToolFailure(tool: "aa", status: result.status, message: result.stderr) }
                    default: throw unsupported(.extract, "Unsupported XIP-stack format")
                    }
                    try Task.checkCancellation()
                    continuation.yield(.init(phase: .extracting, completedUnits: 1, totalUnits: 1))
                    continuation.finish()
                } catch { continuation.finish(throwing: map(error, operation: .extract)) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func create(from sources: [URL], to destination: URL,
                       options: CreationOptions) -> AsyncThrowingStream<ProgressEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: unsupported(.create, "Creation is not enabled for the XIP stack")) }
    }

    public func test(_ handle: ArchiveHandle) -> AsyncThrowingStream<ProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try requireOwnedHandle(handle); let session = try await sessions.get(handle)
                    switch session.format {
                    case .xip:
                        let details = try coordinator.verify(session.url).domainDetails
                        await sessions.setVerification(details, for: handle)
                    case .xar: _ = try xar.inspect(session.url)
                    case .appleArchive: _ = try apple.list(session.url)
                    default: throw unsupported(.test, "Unsupported XIP-stack format")
                    }
                    continuation.yield(.init(phase: .testing, completedUnits: 1, totalUnits: 1))
                    continuation.finish()
                } catch { continuation.finish(throwing: map(error, operation: .test)) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func verificationDetails(for handle: ArchiveHandle) async -> ArchiveVerificationDetails? {
        try? await sessions.get(handle).verification
    }

    public func close(_ handle: ArchiveHandle) async { await sessions.remove(handle) }

    private func unsupported(_ operation: ArchiveOperation, _ message: String) -> ArchiveBackendError {
        .init(.unsupportedOperation, backendIdentifier: identifier.rawValue, operation: operation, message: message)
    }

    private func map(_ error: Error, operation: ArchiveOperation) -> Error {
        if error is CancellationError || (error as? ArchiveBackendError)?.code == .cancelled {
            return ArchiveBackendError(.cancelled, backendIdentifier: identifier.rawValue, operation: operation,
                                       message: "Operation cancelled", diagnosticCode: "USER_CANCELLED")
        }
        if let error = error as? ArchiveBackendError { return error }
        guard let error = error as? XIPStackError else {
            return ArchiveBackendError(.backendFailure, backendIdentifier: identifier.rawValue, operation: operation,
                                       message: String(describing: error), diagnosticCode: "XIP_STACK_FAILURE")
        }
        switch error {
        case .unsupportedLegacyPayload:
            return ArchiveBackendError(.unsupportedOperation, backendIdentifier: identifier.rawValue, operation: operation,
                                       message: "This XIP uses a legacy payload format not supported in this version.",
                                       diagnosticCode: "LEGACY_PBZX_UNSUPPORTED")
        case .unsupportedPayload:
            return ArchiveBackendError(.unsupportedOperation, backendIdentifier: identifier.rawValue, operation: operation,
                                       message: "The XIP payload format is unsupported", diagnosticCode: "XIP_PAYLOAD_UNSUPPORTED")
        case .resourceLimitExceeded:
            return ArchiveBackendError(.resourceLimitExceeded, backendIdentifier: identifier.rawValue, operation: operation,
                                       message: "XAR table of contents exceeds the safety limit", diagnosticCode: "XAR_TOC_LIMIT")
        case .notXAR, .malformedXAR:
            return ArchiveBackendError(.corruptedArchive, backendIdentifier: identifier.rawValue, operation: operation,
                                       message: "The XAR container is malformed", diagnosticCode: "MALFORMED_XAR")
        case .systemToolFailure(let tool, let status, let message):
            return ArchiveBackendError(.backendFailure, backendIdentifier: identifier.rawValue, operation: operation,
                                       message: "System \(tool) operation failed: \(message)", diagnosticCode: "\(tool.uppercased())_\(status)")
        case .appleArchiveFailure(let message):
            return ArchiveBackendError(.corruptedArchive, backendIdentifier: identifier.rawValue, operation: operation,
                                       message: message, diagnosticCode: "APPLE_ARCHIVE_FAILURE")
        }
    }
}

private func kind(for description: String) -> ArchiveEntryKind {
    let value = description.lowercased()
    if value.contains("dir") { return .directory }
    if value.contains("symbolic") || value.contains("symlink") { return .symbolicLink }
    return .regularFile
}

private func xarKind(_ value: String?) -> ArchiveEntryKind {
    switch value?.lowercased() {
    case "directory": .directory
    case "symlink": .symbolicLink
    case "hardlink": .hardLink
    default: .regularFile
    }
}
