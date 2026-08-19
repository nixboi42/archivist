import BackendProtocol
import Domain

/// Routing preference only. Capability truth remains in AuthoritativeCapabilities.
public struct BackendPreferencePolicy: Sendable {
    public init() {}

    public func identifiers(for format: ArchiveFormat, operation: ArchiveOperation) -> [BackendIdentifier] {
        let sevenZip = BackendIdentifier(rawValue: "7zz")
        let libarchive = BackendIdentifier(rawValue: "libarchive")
        let xip = BackendIdentifier(rawValue: "xip-stack")
        let externalRAR = BackendIdentifier(rawValue: "external-rar")
        switch (format, operation) {
        case (.rar, .create): return [externalRAR]
        case (.sevenZip, _), (.zip, _), (.rar, _), (.cab, _), (.arj, _): return [sevenZip, libarchive]
        case (.tar, _), (.tarGzip, _), (.tarBzip2, _), (.tarXZ, _), (.tarZstandard, _),
             (.gzip, _), (.bzip2, _), (.xz, _), (.lzma, _), (.lzip, _), (.unixCompress, _),
             (.zstandard, _), (.cpio, _), (.iso9660, _): return [libarchive, sevenZip]
        case (.xip, _), (.appleArchive, _), (.xar, _): return [xip]
        default: return []
        }
    }
}
