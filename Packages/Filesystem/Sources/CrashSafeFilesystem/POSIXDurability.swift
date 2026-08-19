import Darwin
import Foundation

enum POSIXDurability {
    static func syncFile(at url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw error(.durabilityFailure, url: url, action: "open for durable flush") }
        defer { close(descriptor) }

        if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
        if fsync(descriptor) != 0 {
            throw error(.durabilityFailure, url: url, action: "flush file contents")
        }
    }

    static func syncDirectory(at url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw error(.durabilityFailure, url: url, action: "open directory for durable flush") }
        defer { close(descriptor) }

        guard fsync(descriptor) != 0 else { return }
        if errno != EINVAL && errno != ENOTSUP {
            throw error(.durabilityFailure, url: url, action: "flush directory entry")
        }
    }

    static func atomicRename(from source: URL, to destination: URL) throws {
        guard Darwin.rename(source.path, destination.path) == 0 else {
            throw error(.atomicReplacementFailure, url: destination, action: "atomically replace destination")
        }
    }

    private static func error(_ code: CrashSafeFilesystemError.Code, url: URL, action: String) -> CrashSafeFilesystemError {
        let capturedErrno = errno
        return CrashSafeFilesystemError(
            code,
            path: url.path,
            message: "Could not \(action) at \(url.path): \(String(cString: strerror(capturedErrno)))",
            underlyingErrorCode: capturedErrno
        )
    }
}
