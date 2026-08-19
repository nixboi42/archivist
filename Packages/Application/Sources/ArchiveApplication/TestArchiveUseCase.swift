import BackendProtocol
import BackendRegistry
import Domain
import Foundation

public struct TestArchiveUseCase: Sendable {
    private let registry: ArchiveBackendRegistry
    public init(registry: ArchiveBackendRegistry) { self.registry = registry }

    public func execute(_ archiveURL: URL, credential: ArchiveCredential? = nil,
                        onProgress: @Sendable (ProgressEvent) -> Void = { _ in }) async throws -> TestArchiveResult {
        do {
            let (detection, selection) = try await registry.detectAndSelect(for: archiveURL, operation: .test)
            let handle = try await selection.backend.open(archiveURL, format: detection.format, credential: credential)
            var warnings: [ArchiveWarning] = []
            var details: ArchiveVerificationDetails?
            do {
                for try await event in selection.backend.test(handle) {
                    try Task.checkCancellation()
                    onProgress(event)
                    if let warning = event.warning {
                        warnings.append(.init(.backendWarning, message: warning,
                                              backendIdentifier: selection.backend.identifier.rawValue))
                    }
                }
                details = await (selection.backend as? any DetailedVerificationProviding)?.verificationDetails(for: handle)
                await selection.backend.close(handle)
            } catch {
                await selection.backend.close(handle); throw error
            }
            return .init(format: detection.format, backendIdentifier: selection.backend.identifier,
                         warnings: warnings, details: details)
        } catch { throw ApplicationError.map(error) }
    }

    public func progress(_ archiveURL: URL, credential: ArchiveCredential? = nil) -> AsyncThrowingStream<ProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (detection, selection) = try await registry.detectAndSelect(for: archiveURL, operation: .test)
                    let handle = try await selection.backend.open(archiveURL, format: detection.format, credential: credential)
                    do {
                        for try await event in selection.backend.test(handle) { try Task.checkCancellation(); continuation.yield(event) }
                        await selection.backend.close(handle); continuation.finish()
                    } catch { await selection.backend.close(handle); throw error }
                } catch { continuation.finish(throwing: ApplicationError.map(error)) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
