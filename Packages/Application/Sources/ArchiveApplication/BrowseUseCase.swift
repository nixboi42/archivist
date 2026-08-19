import BackendProtocol
import BackendRegistry
import Domain
import Foundation

public struct BrowseUseCase: Sendable {
    private let registry: ArchiveBackendRegistry
    public init(registry: ArchiveBackendRegistry) { self.registry = registry }

    public func execute(_ request: BrowseRequest) -> AsyncThrowingStream<ArchiveEntry, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (detection, selection) = try await registry.detectAndSelect(for: request.archiveURL, operation: .list)
                    let handle = try await selection.backend.open(request.archiveURL, format: detection.format, credential: request.credential)
                    do {
                        for try await entry in selection.backend.list(handle) {
                            try Task.checkCancellation(); continuation.yield(entry)
                        }
                        await selection.backend.close(handle)
                    } catch {
                        await selection.backend.close(handle); throw error
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: ApplicationError.map(error)) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
