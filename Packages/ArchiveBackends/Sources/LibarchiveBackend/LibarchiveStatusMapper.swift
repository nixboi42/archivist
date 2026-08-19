import CLibarchiveShim
import Domain
import Foundation

public enum LibarchiveStatusMapper {
    public static func error(status: Int32, systemErrno: Int32, message: String,
                             operation: ArchiveOperation) -> ArchiveBackendError? {
        guard status < 0 else { return nil }
        if systemErrno == ECANCELED {
            return .init(.cancelled, backendIdentifier: "libarchive", operation: operation,
                         message: "Operation cancelled", diagnosticCode: "LIBARCHIVE_CANCELLED")
        }
        let code: ArchiveBackendError.Code
        switch systemErrno {
        case EACCES, EPERM: code = .permissionDenied
        case ENOENT, ENOSPC, EROFS: code = .filesystemError
        default: code = status == -20 ? .backendWarning : (operation == .read || operation == .list || operation == .test ? .corruptedArchive : .backendFailure)
        }
        return .init(code, backendIdentifier: "libarchive", operation: operation,
                     message: message.isEmpty ? "libarchive operation failed" : message,
                     diagnosticCode: "LIBARCHIVE_\(status)_ERRNO_\(systemErrno)")
    }
}
