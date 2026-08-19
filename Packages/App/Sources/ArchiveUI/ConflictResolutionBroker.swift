import ArchiveApplication
import Foundation
import OSLog

public actor ConflictResolutionBroker: ConflictResolving {
    private static let logger = Logger(subsystem: "com.keremgurevin.Archivist", category: "conflict-broker")
    public struct Prompt: Identifiable, Sendable {
        public let id = UUID()
        public let context: ConflictContext
    }

    private var continuation: CheckedContinuation<ConflictDecision, Error>?
    private var promptContinuation: AsyncStream<Prompt>.Continuation?
    public nonisolated let prompts: AsyncStream<Prompt>

    public init() {
        var captured: AsyncStream<Prompt>.Continuation?
        prompts = AsyncStream { captured = $0 }
        promptContinuation = captured
    }

    public func resolve(_ context: ConflictContext) async throws -> ConflictDecision {
        guard continuation == nil else {
            throw ApplicationError(.filesystemFailure, message: "A conflict decision is already pending",
                                   diagnosticCode: "CONCURRENT_CONFLICT_PROMPT")
        }
        Self.logger.notice("broker request created; path=\(context.destinationURL.path, privacy: .private(mask: .hash))")
        promptContinuation?.yield(.init(context: context))
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    public func answer(_ decision: ConflictDecision) {
        Self.logger.notice("broker answer; decision=\(decision.resolution.rawValue, privacy: .public); scope=\(decision.scope.rawValue, privacy: .public)")
        continuation?.resume(returning: decision); continuation = nil
    }

    public func cancel() {
        continuation?.resume(throwing: CancellationError()); continuation = nil
    }
}
