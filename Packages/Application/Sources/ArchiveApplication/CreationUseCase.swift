import BackendProtocol
import BackendRegistry
import CrashSafeFilesystem
import Domain
import Foundation

public struct CreationUseCase: Sendable {
    private let registry: ArchiveBackendRegistry
    private let filesystem: CrashSafeFilesystem
    private let conflictResolver: any ConflictResolving

    public init(registry: ArchiveBackendRegistry, filesystem: CrashSafeFilesystem,
                conflictResolver: any ConflictResolving = RejectingConflictResolver()) {
        self.registry = registry; self.filesystem = filesystem; self.conflictResolver = conflictResolver
    }

    public func execute(_ request: CreationRequest) -> AsyncThrowingStream<ProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Select before touching the destination or creating temporary output.
                    let selection = try await registry.select(format: request.options.format, operation: .create)
                    guard let creationCapabilities = selection.capabilities.creationOptions else {
                        throw ApplicationError(.unsupportedOperation, message: "Creation options are not verified for this format",
                                               diagnosticCode: "CREATION_OPTIONS_UNVERIFIED")
                    }
                    do { try request.options.validate(against: creationCapabilities) }
                    catch {
                        throw ApplicationError(.unsupportedOperation, message: "The selected creation options are not supported",
                                               diagnosticCode: "INVALID_CREATION_OPTIONS")
                    }
                    try await approveExistingDestination(request)
                    if request.options.volumeSize != nil {
                        _ = try await filesystem.replaceArchiveSet(at: request.destinationURL) { candidate in
                            for try await progress in selection.backend.create(from: request.sourceURLs, to: candidate,
                                                                               options: request.options) {
                                try Task.checkCancellation(); continuation.yield(progress)
                            }
                        } validate: { firstVolume in
                            try await validate(firstVolume, selection: selection, request: request, continuation: continuation)
                        }
                    } else {
                        try await filesystem.replaceArchive(at: request.destinationURL) { candidate in
                        for try await progress in selection.backend.create(from: request.sourceURLs, to: candidate,
                                                                           options: request.options) {
                            try Task.checkCancellation(); continuation.yield(progress)
                        }
                    } validate: { candidate in
                        try await validate(candidate, selection: selection, request: request, continuation: continuation)
                    }
                    }
                    continuation.yield(.init(phase: .finalizing, completedUnits: 1, totalUnits: 1))
                    continuation.finish()
                } catch { continuation.finish(throwing: ApplicationError.map(error)) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func validate(_ candidate: URL, selection: BackendSelection, request: CreationRequest,
                          continuation: AsyncThrowingStream<ProgressEvent, Error>.Continuation) async throws {
        let handle = try await selection.backend.open(candidate, format: request.options.format,
                                                      credential: request.options.credential)
        do {
            for try await progress in selection.backend.test(handle) {
                try Task.checkCancellation(); continuation.yield(progress)
            }
            await selection.backend.close(handle)
        } catch { await selection.backend.close(handle); throw error }
    }

    private func approveExistingDestination(_ request: CreationRequest) async throws {
        let conflictURL = request.options.volumeSize == nil ? request.destinationURL
            : URL(fileURLWithPath: request.destinationURL.path + ".001")
        guard FileManager.default.fileExists(atPath: conflictURL.path) else { return }
        switch request.overwritePolicy {
        case .replace: return
        case .skip:
            throw ApplicationError(.filesystemFailure, message: "Destination already exists",
                                   diagnosticCode: "DESTINATION_SKIPPED")
        case .keepBoth:
            throw ApplicationError(.unsupportedOperation, message: "Keep-both creation requires a distinct destination URL",
                                   diagnosticCode: "KEEP_BOTH_DESTINATION_REQUIRED")
        case .ask:
            let decision = try await conflictResolver.resolve(.init(destinationURL: conflictURL, entry: nil))
            guard decision.resolution == .replace else {
                throw ApplicationError(.filesystemFailure, message: "Destination replacement was not approved",
                                       diagnosticCode: "DESTINATION_NOT_REPLACED")
            }
        }
    }
}
