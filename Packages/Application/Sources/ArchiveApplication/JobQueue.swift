import Domain
import Foundation

public enum JobState: Hashable, Sendable {
    case queued
    case running
    case completed
    case failed(ApplicationError)
    case cancelled
}

public struct JobSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let descriptor: JobDescriptor
    public let state: JobState
    public let attempt: Int
    public let latestProgress: ProgressEvent?
}

public typealias JobOperation = @Sendable (@escaping @Sendable (ProgressEvent) -> Void) async throws -> Void

private struct QueuedJob: Sendable {
    let descriptor: JobDescriptor
    let operation: JobOperation
    var state: JobState
    var attempt: Int
    var latestProgress: ProgressEvent?
}

public actor JobQueue {
    public let maximumConcurrentJobs: Int
    private var jobs: [UUID: QueuedJob] = [:]
    private var fifo: [UUID] = []
    private var runningTasks: [UUID: Task<Void, Never>] = [:]

    public init(maximumConcurrentJobs: Int) {
        self.maximumConcurrentJobs = max(1, maximumConcurrentJobs)
    }

    @discardableResult
    public func enqueue(_ descriptor: JobDescriptor, operation: @escaping JobOperation) -> UUID {
        guard jobs[descriptor.id] == nil else { return descriptor.id }
        jobs[descriptor.id] = .init(descriptor: descriptor, operation: operation, state: .queued,
                                    attempt: 1, latestProgress: nil)
        fifo.append(descriptor.id)
        schedule()
        return descriptor.id
    }

    public func cancel(_ id: UUID) {
        guard var job = jobs[id] else { return }
        switch job.state {
        case .queued:
            fifo.removeAll { $0 == id }; job.state = .cancelled; jobs[id] = job
        case .running:
            runningTasks[id]?.cancel()
        default: break
        }
    }

    public func retry(_ id: UUID) throws {
        guard var job = jobs[id] else {
            throw ApplicationError(.backendFailure, message: "Unknown job", diagnosticCode: "UNKNOWN_JOB")
        }
        switch job.state {
        case .failed, .cancelled:
            guard runningTasks[id] == nil, !fifo.contains(id) else { return }
            job.state = .queued; job.attempt += 1; job.latestProgress = nil
            jobs[id] = job; fifo.append(id); schedule()
        default:
            throw ApplicationError(.backendFailure, message: "Only failed or cancelled jobs can be retried",
                                   diagnosticCode: "INVALID_RETRY_STATE")
        }
    }

    public func snapshot(_ id: UUID) -> JobSnapshot? {
        guard let job = jobs[id] else { return nil }
        return .init(id: id, descriptor: job.descriptor, state: job.state,
                     attempt: job.attempt, latestProgress: job.latestProgress)
    }

    public func snapshots() -> [JobSnapshot] {
        jobs.map { .init(id: $0.key, descriptor: $0.value.descriptor, state: $0.value.state,
                         attempt: $0.value.attempt, latestProgress: $0.value.latestProgress) }
            .sorted { lhs, rhs in
                lhs.descriptor.createdAt == rhs.descriptor.createdAt
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.descriptor.createdAt < rhs.descriptor.createdAt
            }
    }

    private func schedule() {
        while runningTasks.count < maximumConcurrentJobs, !fifo.isEmpty {
            let id = fifo.removeFirst()
            guard var job = jobs[id], job.state == .queued else { continue }
            job.state = .running; jobs[id] = job
            let operation = job.operation
            runningTasks[id] = Task {
                do {
                    try await operation { progress in Task { await self.record(progress, for: id) } }
                    try Task.checkCancellation()
                    self.finish(id, result: .success(()))
                } catch {
                    self.finish(id, result: .failure(error))
                }
            }
        }
    }

    private func record(_ progress: ProgressEvent, for id: UUID) {
        guard var job = jobs[id], job.state == .running else { return }
        job.latestProgress = progress; jobs[id] = job
    }

    private func finish(_ id: UUID, result: Result<Void, Error>) {
        guard var job = jobs[id], job.state == .running else { return }
        runningTasks.removeValue(forKey: id)
        switch result {
        case .success: job.state = .completed
        case .failure(let error):
            let mapped = ApplicationError.map(error)
            job.state = mapped.code == .cancelled ? .cancelled : .failed(mapped)
        }
        jobs[id] = job
        schedule()
    }
}
