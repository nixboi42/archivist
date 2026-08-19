import Foundation

public struct CrashSafeFilesystemError: Error, Hashable, Sendable, CustomStringConvertible {
    public enum Code: String, Hashable, Sendable {
        case destinationHasNoParent
        case temporaryOutputMissing
        case temporaryOutputNotRegularFile
        case differentVolume
        case partialFileAlreadyExists
        case durabilityFailure
        case atomicReplacementFailure
        case filesystemFailure
    }

    public let code: Code
    public let path: String
    public let message: String
    public let underlyingErrorCode: Int32?

    public init(_ code: Code, path: String, message: String, underlyingErrorCode: Int32? = nil) {
        self.code = code
        self.path = path
        self.message = message
        self.underlyingErrorCode = underlyingErrorCode
    }

    public var description: String { message }
}
