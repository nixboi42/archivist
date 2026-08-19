public struct ArchiveBackendError: Error, Codable, Hashable, Sendable, CustomStringConvertible {
    public enum Code: String, Codable, Hashable, Sendable {
        case unsupportedFormat, unsupportedOperation, invalidArchive, passwordRequired, incorrectPassword,
             permissionDenied, destinationUnavailable, insufficientSpace, resourceLimitExceeded,
             unsafeArchive, cancelled, timedOut, backendUnavailable, backendCrashed, backendFailure,
             corruptedArchive, filesystemError, malformedMetadata, backendWarning,
             noAvailableBackend, preferredBackendUnavailable
    }

    public let code: Code
    public let backendIdentifier: String?
    public let operation: ArchiveOperation?
    public let message: String
    public let diagnosticCode: String?

    public init(_ code: Code, backendIdentifier: String? = nil, operation: ArchiveOperation? = nil,
                message: String, diagnosticCode: String? = nil) {
        self.code = code
        self.backendIdentifier = backendIdentifier
        self.operation = operation
        self.message = message
        self.diagnosticCode = diagnosticCode
    }

    public var description: String { message }
}
