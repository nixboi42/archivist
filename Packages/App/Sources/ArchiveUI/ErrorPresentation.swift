import ArchiveApplication
import Foundation

public struct ErrorPresentation: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let details: String?

    public init(_ error: ApplicationError) {
        title = switch error.code {
        case .unsupportedFormat: "Unsupported Archive"
        case .unsupportedOperation: "Operation Not Supported"
        case .noBackendAvailable: "Required Backend Unavailable"
        case .wrongPassword: "Password Required"
        case .corruptedArchive: "Archive Appears Corrupted"
        case .unsafeArchiveEntry: "Unsafe Archive Entry"
        case .insufficientSpace: "Not Enough Space"
        case .filesystemFailure: "File Operation Failed"
        case .backendCrash: "Archive Helper Stopped"
        case .backendFailure: "Archive Operation Failed"
        case .cancelled: "Operation Cancelled"
        }
        message = switch error.code {
        case .corruptedArchive: "The archive could not be processed because it appears to be corrupted."
        case .unsafeArchiveEntry: "The operation was stopped because an entry did not satisfy the security policy."
        case .wrongPassword: "Enter the archive password and try again."
        default: error.message
        }
        details = [error.backendIdentifier, error.diagnosticCode].compactMap { $0 }.isEmpty
            ? nil : [error.backendIdentifier, error.diagnosticCode].compactMap { $0 }.joined(separator: " · ")
    }
}
