import CrashSafeFilesystem
import Domain
import Foundation
import ArchiveSecurity

public struct ApplicationError: Error, Hashable, Sendable, CustomStringConvertible {
    public enum Code: String, Hashable, Sendable {
        case unsupportedFormat, unsupportedOperation, noBackendAvailable
        case wrongPassword, corruptedArchive, unsafeArchiveEntry, insufficientSpace
        case filesystemFailure, backendCrash, backendFailure, cancelled
    }

    public let code: Code
    public let message: String
    public let backendIdentifier: String?
    public let diagnosticCode: String?

    public init(_ code: Code, message: String, backendIdentifier: String? = nil, diagnosticCode: String? = nil) {
        self.code = code; self.message = message; self.backendIdentifier = backendIdentifier; self.diagnosticCode = diagnosticCode
    }

    public var description: String { message }

    public static func map(_ error: Error) -> ApplicationError {
        if error is CancellationError {
            return .init(.cancelled, message: "The operation was cancelled", diagnosticCode: "USER_CANCELLED")
        }
        if let error = error as? ApplicationError { return error }
        if let error = error as? ArchiveBackendError {
            let code: Code = switch error.code {
            case .unsupportedFormat: .unsupportedFormat
            case .unsupportedOperation: .unsupportedOperation
            case .noAvailableBackend, .preferredBackendUnavailable, .backendUnavailable: .noBackendAvailable
            case .incorrectPassword, .passwordRequired: .wrongPassword
            case .invalidArchive, .corruptedArchive, .malformedMetadata: .corruptedArchive
            case .unsafeArchive: .unsafeArchiveEntry
            case .insufficientSpace, .resourceLimitExceeded: .insufficientSpace
            case .filesystemError, .destinationUnavailable, .permissionDenied: .filesystemFailure
            case .backendCrashed: .backendCrash
            case .cancelled: .cancelled
            default: .backendFailure
            }
            return .init(code, message: error.message, backendIdentifier: error.backendIdentifier,
                         diagnosticCode: error.diagnosticCode)
        }
        if let error = error as? CrashSafeFilesystemError {
            return .init(.filesystemFailure, message: error.message,
                         diagnosticCode: "FILESYSTEM_\(error.code.rawValue.uppercased())")
        }
        if let error = error as? ArchiveSecurityError {
            let code: Code = error.code == .insufficientDiskSpace ? .insufficientSpace : .unsafeArchiveEntry
            return .init(code, message: "Archive security policy rejected \(error.entryPath ?? "an entry")",
                         diagnosticCode: "SECURITY_\(error.code.rawValue.uppercased())")
        }
        return .init(.backendFailure, message: String(describing: error), diagnosticCode: "UNMAPPED_ERROR")
    }
}
