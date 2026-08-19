import Domain

public struct SevenZipExitCodeMapper: Sendable {
    public init() {}
    public func error(exitCode: Int32?, signal: Int32?, cancellationRequested: Bool, operation: ArchiveOperation) -> ArchiveBackendError? {
        if cancellationRequested { return .init(.cancelled, backendIdentifier: "7zz", operation: operation, message: "Operation cancelled") }
        if let signal { return .init(.backendCrashed, backendIdentifier: "7zz", operation: operation, message: "7zz terminated by signal", diagnosticCode: "SIGNAL_\(signal)") }
        switch exitCode {
        case 0: return nil
        case 1: return .init(.backendFailure, backendIdentifier: "7zz", operation: operation, message: "7zz completed with warnings", diagnosticCode: "EXIT_1")
        case 2: return .init(.invalidArchive, backendIdentifier: "7zz", operation: operation, message: "Archive operation failed", diagnosticCode: "EXIT_2")
        case 7: return .init(.backendFailure, backendIdentifier: "7zz", operation: operation, message: "Backend command rejected", diagnosticCode: "EXIT_7")
        case 8: return .init(.resourceLimitExceeded, backendIdentifier: "7zz", operation: operation, message: "7zz ran out of memory", diagnosticCode: "EXIT_8")
        case 255: return .init(.backendCrashed, backendIdentifier: "7zz", operation: operation, message: "7zz terminated without cancellation intent", diagnosticCode: "EXIT_255")
        default: return .init(.backendFailure, backendIdentifier: "7zz", operation: operation, message: "Unexpected 7zz failure", diagnosticCode: exitCode.map { "EXIT_\($0)" })
        }
    }
}
